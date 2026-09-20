use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Json, Response},
    routing::{get, post},
    Router,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Duration;

// ===================== 配置 =====================

#[derive(Clone)]
struct AppState {
    inner: Arc<Inner>,
}

struct Inner {
    portainer_url: String,
    token: String,
    endpoints: HashMap<String, i64>,
    client: Client,
}

impl Inner {
    fn get(&self, path: &str) -> reqwest::RequestBuilder {
        self.client
            .get(format!("{}{}", self.portainer_url, path))
            .header("X-API-Key", &self.token)
    }
    fn post(&self, path: &str) -> reqwest::RequestBuilder {
        self.client
            .post(format!("{}{}", self.portainer_url, path))
            .header("X-API-Key", &self.token)
    }
    fn delete(&self, path: &str) -> reqwest::RequestBuilder {
        self.client
            .delete(format!("{}{}", self.portainer_url, path))
            .header("X-API-Key", &self.token)
    }
}

// ===================== 数据结构 =====================

#[derive(Deserialize)]
struct PortainerStack {
    #[serde(rename = "Id")]
    id: i64,
    #[serde(rename = "Name")]
    name: String,
    #[serde(rename = "EndpointId")]
    endpoint_id: i64,
    #[serde(rename = "Status")]
    status: i64,
}

#[derive(Serialize)]
struct StackView {
    id: i64,
    name: String,
    status: i64,
    status_text: String,
}

#[derive(Serialize)]
struct PcView {
    name: String,
    endpoint_id: i64,
    stacks: Vec<StackView>,
}

#[derive(Serialize)]
struct StatusResponse {
    pcs: Vec<PcView>,
    classes: Vec<String>,
}

#[derive(Deserialize)]
struct StartRequest {
    pc: String,
    class: String,
}

#[derive(Serialize)]
struct StartResult {
    pc: String,
    class: String,
    started: bool,
    cleaned: usize,
}

#[derive(Deserialize)]
struct BatchItem {
    pc: String,
    class: String,
}

#[derive(Deserialize)]
struct BatchRequest {
    items: Vec<BatchItem>,
}

#[derive(Serialize)]
struct BatchItemResult {
    pc: String,
    class: String,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
    cleaned: usize,
}

#[derive(Serialize)]
struct BatchResult {
    results: Vec<BatchItemResult>,
    success: usize,
    failed: usize,
}

#[derive(Serialize)]
struct ApiResult<T: Serialize> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

#[derive(Deserialize)]
struct DockerContainer {
    #[serde(rename = "Id")]
    id: String,
    #[serde(rename = "Names")]
    names: Vec<String>,
}

// ===================== 工具函数 =====================

fn status_text(s: i64) -> &'static str {
    match s {
        1 => "active",
        2 => "inactive",
        3 => "error",
        4 => "removed",
        _ => "unknown",
    }
}

fn parse_endpoint_map(s: &str) -> HashMap<String, i64> {
    let mut m = HashMap::new();
    for pair in s.split(',') {
        let pair = pair.trim();
        if pair.is_empty() {
            continue;
        }
        if let Some((k, v)) = pair.split_once('=') {
            if let Ok(id) = v.trim().parse::<i64>() {
                m.insert(k.trim().to_string(), id);
            }
        }
    }
    m
}

struct AppError(StatusCode, String);

fn err(status: StatusCode, msg: impl Into<String>) -> AppError {
    AppError(status, msg.into())
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let body = ApiResult::<()> {
            ok: false,
            data: None,
            message: Some(self.1),
        };
        (self.0, Json(body)).into_response()
    }
}

fn ok<T: Serialize>(data: T) -> Json<ApiResult<T>> {
    Json(ApiResult {
        ok: true,
        data: Some(data),
        message: None,
    })
}

// ===================== Portainer 调用 =====================

async fn list_stacks(inner: &Inner) -> Result<Vec<PortainerStack>, AppError> {
    let resp = inner
        .get("/api/stacks")
        .send()
        .await
        .map_err(|e| err(StatusCode::BAD_GATEWAY, format!("Portainer 不可达: {e}")))?;
    if !resp.status().is_success() {
        return Err(err(resp.status(), "获取 stack 列表失败"));
    }
    resp.json::<Vec<PortainerStack>>()
        .await
        .map_err(|e| err(StatusCode::BAD_GATEWAY, format!("解析 stack 列表失败: {e}")))
}

async fn get_stack_file(inner: &Inner, stack_id: i64) -> String {
    let resp = inner.get(&format!("/api/stacks/{stack_id}/file")).send().await;
    if let Ok(r) = resp {
        if r.status().is_success() {
            if let Ok(v) = r.json::<serde_json::Value>().await {
                return v["StackFileContent"].as_str().unwrap_or("").to_string();
            }
        }
    }
    String::new()
}

fn extract_container_names(compose: &str) -> Vec<String> {
    let re = regex::Regex::new(r#"container_name:\s*['"]?([A-Za-z0-9_-]+)"#).unwrap();
    re.captures_iter(compose).map(|c| c[1].to_string()).collect()
}

async fn cleanup_containers(inner: &Inner, endpoint_id: i64, expected: &[String]) -> usize {
    let expected: HashSet<&str> = expected.iter().map(|s| s.as_str()).collect();
    let resp = inner
        .get(&format!(
            "/api/endpoints/{endpoint_id}/docker/containers/json?all=true"
        ))
        .send()
        .await;
    let containers: Vec<DockerContainer> = match resp {
        Ok(r) if r.status().is_success() => r.json().await.unwrap_or_default(),
        _ => return 0,
    };
    let mut removed = 0;
    for c in &containers {
        for n in &c.names {
            let cn = n.trim_start_matches('/');
            if expected.contains(cn) {
                let del = inner
                    .delete(&format!(
                        "/api/endpoints/{endpoint_id}/docker/containers/{}?force=true",
                        c.id
                    ))
                    .send()
                    .await;
                if matches!(del.map(|r| r.status()), Ok(s) if s.is_success()) {
                    removed += 1;
                }
            }
        }
    }
    removed
}

// ===================== 路由处理 =====================

const HTML: &str = include_str!("../static/index.html");

async fn index() -> Html<&'static str> {
    Html(HTML)
}

async fn status(State(state): State<AppState>) -> Result<Json<StatusResponse>, AppError> {
    let inner = &state.inner;
    let stacks = list_stacks(inner).await?;

    let mut classes: HashSet<String> = HashSet::new();
    let mut pcs: Vec<PcView> = Vec::new();

    let mut names: Vec<&String> = inner.endpoints.keys().collect();
    names.sort();

    for pc_name in names {
        let ep = *inner.endpoints.get(pc_name).unwrap();
        let pc_stacks: Vec<StackView> = stacks
            .iter()
            .filter(|s| s.endpoint_id == ep)
            .map(|s| {
                classes.insert(s.name.clone());
                StackView {
                    id: s.id,
                    name: s.name.clone(),
                    status: s.status,
                    status_text: status_text(s.status).to_string(),
                }
            })
            .collect();
        pcs.push(PcView {
            name: pc_name.clone(),
            endpoint_id: ep,
            stacks: pc_stacks,
        });
    }

    let mut classes: Vec<String> = classes.into_iter().collect();
    classes.sort();

    Ok(Json(StatusResponse { pcs, classes }))
}

async fn do_start(inner: &Inner, pc: &str, class: &str) -> Result<StartResult, String> {
    let endpoint_id = inner
        .endpoints
        .get(pc)
        .copied()
        .ok_or_else(|| format!("未知 PC: {pc}"))?;

    let stacks = list_stacks(inner).await.map_err(|e| e.1)?;

    let target = stacks
        .iter()
        .find(|s| s.endpoint_id == endpoint_id && s.name == class)
        .ok_or_else(|| format!("在 {pc} 上未找到 stack {class}"))?;
    let target_id = target.id;

    // 先停止该 PC 上其他正在运行的 stack
    for s in &stacks {
        if s.endpoint_id == endpoint_id && s.name != class && s.status == 1 {
            let _ = inner
                .post(&format!(
                    "/api/stacks/{}/stop?endpointId={}",
                    s.id, endpoint_id
                ))
                .send()
                .await;
        }
    }

    // 已经在运行
    if target.status == 1 {
        return Ok(StartResult {
            pc: pc.to_string(),
            class: class.to_string(),
            started: true,
            cleaned: 0,
        });
    }

    let start_url = format!("/api/stacks/{target_id}/start?endpointId={endpoint_id}");
    let resp = inner
        .post(&start_url)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let mut cleaned = 0;

    if resp.status() == reqwest::StatusCode::CONFLICT {
        // 409 容器名冲突 -> 清理孤儿容器 -> 重试
        let compose = get_stack_file(inner, target_id).await;
        let expected = extract_container_names(&compose);
        cleaned = cleanup_containers(inner, endpoint_id, &expected).await;
        tokio::time::sleep(Duration::from_secs(2)).await;

        let resp2 = inner
            .post(&start_url)
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if !resp2.status().is_success() {
            let body = resp2.text().await.unwrap_or_default();
            return Err(format!("清理冲突后启动仍失败: {body}"));
        }
    } else if !resp.status().is_success() {
        let body = resp.text().await.unwrap_or_default();
        return Err(format!("启动失败: {body}"));
    }

    Ok(StartResult {
        pc: pc.to_string(),
        class: class.to_string(),
        started: true,
        cleaned,
    })
}

async fn do_stop_single(inner: &Inner, pc: &str, class: &str) -> Result<(), String> {
    let endpoint_id = inner
        .endpoints
        .get(pc)
        .copied()
        .ok_or_else(|| format!("未知 PC: {pc}"))?;
    let stacks = list_stacks(inner).await.map_err(|e| e.1)?;
    let target = stacks
        .iter()
        .find(|s| s.endpoint_id == endpoint_id && s.name == class)
        .ok_or_else(|| format!("在 {pc} 上未找到 stack {class}"))?;
    if target.status == 1 {
        let resp = inner
            .post(&format!(
                "/api/stacks/{}/stop?endpointId={}",
                target.id, endpoint_id
            ))
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("停止失败: {body}"));
        }
    }
    Ok(())
}

async fn start_class(
    State(state): State<AppState>,
    Json(req): Json<StartRequest>,
) -> Result<Json<ApiResult<StartResult>>, AppError> {
    match do_start(&state.inner, &req.pc, &req.class).await {
        Ok(r) => Ok(ok(r)),
        Err(m) => Err(err(StatusCode::BAD_GATEWAY, m)),
    }
}

async fn batch_start(
    State(state): State<AppState>,
    Json(req): Json<BatchRequest>,
) -> Result<Json<ApiResult<BatchResult>>, AppError> {
    let inner = &state.inner;
    let mut results = Vec::new();
    let mut success = 0usize;
    let mut failed = 0usize;
    for it in &req.items {
        match do_start(inner, &it.pc, &it.class).await {
            Ok(r) => {
                success += 1;
                results.push(BatchItemResult {
                    pc: it.pc.clone(),
                    class: it.class.clone(),
                    ok: true,
                    message: None,
                    cleaned: r.cleaned,
                });
            }
            Err(m) => {
                failed += 1;
                results.push(BatchItemResult {
                    pc: it.pc.clone(),
                    class: it.class.clone(),
                    ok: false,
                    message: Some(m),
                    cleaned: 0,
                });
            }
        }
    }
    Ok(ok(BatchResult {
        results,
        success,
        failed,
    }))
}

async fn batch_stop(
    State(state): State<AppState>,
    Json(req): Json<BatchRequest>,
) -> Result<Json<ApiResult<BatchResult>>, AppError> {
    let inner = &state.inner;
    let mut results = Vec::new();
    let mut success = 0usize;
    let mut failed = 0usize;
    for it in &req.items {
        match do_stop_single(inner, &it.pc, &it.class).await {
            Ok(()) => {
                success += 1;
                results.push(BatchItemResult {
                    pc: it.pc.clone(),
                    class: it.class.clone(),
                    ok: true,
                    message: None,
                    cleaned: 0,
                });
            }
            Err(m) => {
                failed += 1;
                results.push(BatchItemResult {
                    pc: it.pc.clone(),
                    class: it.class.clone(),
                    ok: false,
                    message: Some(m),
                    cleaned: 0,
                });
            }
        }
    }
    Ok(ok(BatchResult {
        results,
        success,
        failed,
    }))
}

async fn stop_all(State(state): State<AppState>) -> Result<Json<ApiResult<()>>, AppError> {
    let inner = &state.inner;
    let stacks = list_stacks(inner).await?;
    for s in &stacks {
        if s.status == 1 {
            let _ = inner
                .post(&format!(
                    "/api/stacks/{}/stop?endpointId={}",
                    s.id, s.endpoint_id
                ))
                .send()
                .await;
        }
    }
    Ok(ok(()))
}

// ===================== 入口 =====================

#[tokio::main]
async fn main() {
    let portainer_url = std::env::var("PORTAINER_URL")
        .unwrap_or_else(|_| "http://10.22.27.32:9000".to_string());
    let token = std::env::var("PORTAINER_TOKEN").expect("环境变量 PORTAINER_TOKEN 必填");
    let endpoint_map_str = std::env::var("ENDPOINT_MAP").unwrap_or_else(|_| {
        "pc01=3,pc02=4,pc03=6,pc04=7,pc05=8,pc06=9,pc07=10,pc08=11,pc09=12".to_string()
    });
    let endpoints = parse_endpoint_map(&endpoint_map_str);

    let client = Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .unwrap();

    let inner = Arc::new(Inner {
        portainer_url,
        token,
        endpoints,
        client,
    });
    let state = AppState { inner };

    let app = Router::new()
        .route("/", get(index))
        .route("/api/status", get(status))
        .route("/api/start", post(start_class))
        .route("/api/stop-all", post(stop_all))
        .route("/api/batch-start", post(batch_start))
        .route("/api/batch-stop", post(batch_stop))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .unwrap();
    println!("班级控制面板已启动: http://0.0.0.0:8080");
    axum::serve(listener, app).await.unwrap();
}
