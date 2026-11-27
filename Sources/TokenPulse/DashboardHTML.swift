import Foundation

enum DashboardHTML {
    static let content: String = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>TokenPulse</title>
<style>
  :root {
    --bg: #f6f8fb;
    --surface: #ffffff;
    --surface-2: #f1f5f9;
    --border: rgba(15, 23, 42, 0.08);
    --border-strong: rgba(15, 23, 42, 0.16);
    --text: #0f172a;
    --text-2: #475569;
    --text-3: #94a3b8;
    --gpt: #059669;
    --gpt-soft: rgba(16, 185, 129, 0.12);
    --gemini: #0284c7;
    --gemini-soft: rgba(14, 165, 233, 0.12);
    --claude: #8b5cf6;
    --claude-soft: rgba(139, 92, 246, 0.12);
    --amber: #d97706;
    --amber-soft: rgba(245, 158, 11, 0.12);
    --blue: #2563eb;
    --radius: 12px;
    --shadow-sm: 0 1px 2px rgba(15, 23, 42, 0.04), 0 1px 1px rgba(15, 23, 42, 0.02);
  }

  * {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    font-style: normal !important;
    -webkit-user-select: none;
    user-select: none;
  }

  html, body {
    width: 100%;
    height: 100%;
    background: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
    font-size: 13px;
    line-height: 1.45;
    overflow: hidden;
    -webkit-font-smoothing: antialiased;
  }

  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
    position: relative;
    background:
      radial-gradient(420px 160px at 15% -12%, rgba(56, 189, 248, 0.14), transparent 70%),
      radial-gradient(360px 150px at 88% -12%, rgba(16, 185, 129, 0.10), transparent 70%),
      var(--bg);
  }

  .app.state-needs-action {
    background:
      radial-gradient(460px 180px at 50% -15%, rgba(245, 158, 11, 0.18), transparent 70%),
      var(--bg);
  }

  /* Header */
  .header {
    padding: 14px 16px 10px;
    border-bottom: 1px solid var(--border);
    background: rgba(255, 255, 255, 0.72);
    backdrop-filter: blur(14px);
    flex-shrink: 0;
  }

  .header-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 10px;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .brand-logo {
    width: 24px;
    height: 24px;
    border-radius: 7px;
    background: linear-gradient(135deg, #0ea5e9 0%, #2563eb 100%);
    box-shadow: 0 2px 6px rgba(14, 165, 233, 0.28);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .brand-name {
    font-size: 15px;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: var(--text);
  }

  .status-pill {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    background: rgba(16, 185, 129, 0.12);
    color: #059669;
    border: 1px solid rgba(16, 185, 129, 0.24);
  }

  .status-pill.running {
    background: rgba(14, 165, 233, 0.12);
    color: #0284c7;
    border-color: rgba(14, 165, 233, 0.28);
  }

  .status-pill.needs-action {
    background: rgba(245, 158, 11, 0.14);
    color: #d97706;
    border-color: rgba(245, 158, 11, 0.36);
  }

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }

  .dot.pulse {
    animation: pulseAnim 1.5s infinite ease-in-out;
  }

  @keyframes pulseAnim {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.4; transform: scale(0.8); }
  }

  .icon-actions {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .icon-btn {
    width: 28px;
    height: 28px;
    border-radius: 8px;
    border: 1px solid transparent;
    background: transparent;
    color: var(--text-2);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s ease;
  }

  .icon-btn:hover {
    background: rgba(15, 23, 42, 0.05);
    color: var(--text);
    border-color: var(--border);
  }

  .icon-btn.spinning svg {
    animation: spin 0.7s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  /* Filter Pills */
  .filters {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .pill-group {
    display: inline-flex;
    background: rgba(15, 23, 42, 0.05);
    border: 1px solid var(--border);
    border-radius: 9px;
    padding: 2px;
    gap: 2px;
  }

  .pill-btn {
    border: none;
    background: transparent;
    color: var(--text-2);
    font-size: 11px;
    font-weight: 500;
    padding: 4px 8px;
    border-radius: 7px;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .pill-btn:hover {
    color: var(--text);
  }

  .pill-btn.active {
    background: #ffffff;
    color: var(--text);
    font-weight: 600;
    box-shadow: 0 1px 3px rgba(15, 23, 42, 0.09), 0 0 0 1px rgba(15, 23, 42, 0.04);
  }

  /* Main Scroll Area */
  .content {
    flex: 1;
    overflow-y: auto;
    padding: 14px 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .content::-webkit-scrollbar {
    width: 5px;
  }

  .content::-webkit-scrollbar-thumb {
    background: rgba(15, 23, 42, 0.14);
    border-radius: 99px;
  }

  /* Needs Action Alert */
  .alert-card {
    background: linear-gradient(135deg, #fffbeb, #fef3c7);
    border: 1px solid rgba(217, 119, 6, 0.30);
    border-radius: var(--radius);
    padding: 10px 12px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    box-shadow: var(--shadow-sm);
  }

  .alert-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 12px;
    font-weight: 600;
    color: #b45309;
  }

  .alert-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    background: #ffffff;
    border: 1px solid rgba(217, 119, 6, 0.18);
    border-radius: 9px;
    padding: 8px 10px;
  }

  [data-focus-app] {
    cursor: pointer;
  }

  .alert-item:hover {
    border-color: rgba(217, 119, 6, 0.40);
  }

  .alert-meta {
    min-width: 0;
    flex: 1;
  }

  .alert-title {
    font-size: 12px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .alert-sub {
    font-size: 11px;
    color: var(--text-2);
    margin-top: 2px;
  }

  .dismiss-btn {
    border: 1px solid var(--border-strong);
    background: var(--bg);
    color: var(--text-2);
    font-size: 11px;
    padding: 3px 9px;
    border-radius: 6px;
    cursor: pointer;
    flex-shrink: 0;
    transition: all 0.15s;
  }

  .dismiss-btn:hover {
    background: var(--surface-2);
    color: var(--text);
  }

  /* Hero KPI Cards */
  .hero-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
  }

  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 12px;
    position: relative;
    overflow: visible;
    box-shadow: var(--shadow-sm);
  }

  .hero-grid .card {
    display: flex;
    flex-direction: column;
  }

  .hero-grid .sparkline-wrap {
    margin-top: auto;
    padding-top: 6px;
  }

  .card-label {
    font-size: 11px;
    font-weight: 500;
    color: var(--text-2);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .card-value {
    font-size: 24px;
    font-weight: 700;
    letter-spacing: -0.03em;
    font-variant-numeric: tabular-nums;
    margin-top: 4px;
    color: var(--text);
  }

  .card-value.accent-blue {
    background: linear-gradient(90deg, #0284c7, #4f46e5);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }

  .card-sub {
    font-size: 11px;
    color: var(--text-3);
    margin-top: 3px;
    font-variant-numeric: tabular-nums;
  }

  .sparkline-wrap {
    margin-top: 6px;
    position: relative;
    width: 100%;
    cursor: crosshair;
  }

  .sparkline-svg {
    display: block;
    width: 100%;
    height: 30px;
  }

  .token-bar {
    fill: #34d399;
  }

  .token-bar.empty-bar {
    fill: #e2e8f0;
  }

  .token-bar.highlighted {
    fill: #059669;
  }

  .spark-axis {
    display: flex;
    justify-content: space-between;
    font-size: 9.5px;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
    margin-top: 2px;
  }

  .spark-tip {
    position: absolute;
    bottom: 100%;
    margin-bottom: 5px;
    padding: 4px 7px;
    border-radius: 7px;
    background: rgba(15, 23, 42, 0.94);
    color: #ffffff;
    font-size: 10px;
    line-height: 1.3;
    white-space: nowrap;
    pointer-events: none;
    box-shadow: 0 4px 12px rgba(15, 23, 42, 0.22);
    z-index: 20;
    opacity: 0;
    transform: translateY(2px);
    transition: opacity 0.12s ease, transform 0.12s ease;
  }

  .spark-tip.visible {
    opacity: 1;
    transform: translateY(0);
  }

  .spark-tip-val {
    font-weight: 700;
    color: #38bdf8;
    font-variant-numeric: tabular-nums;
  }

  .spark-tip-sub {
    color: #cbd5e1;
    font-size: 9.5px;
    margin-top: 1px;
  }

  /* Sub-metrics + Split Bar */
  .split-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 11px 12px;
    display: flex;
    flex-direction: column;
    gap: 9px;
    box-shadow: var(--shadow-sm);
  }

  .sub-stats {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 8px;
  }

  .mini-stat {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .mini-label {
    font-size: 10px;
    color: var(--text-3);
  }

  .mini-val {
    font-size: 13px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: var(--text);
  }

  .bar-track {
    height: 6px;
    width: 100%;
    background: #e2e8f0;
    border-radius: 99px;
    overflow: hidden;
    display: flex;
  }

  .bar-gpt {
    background: linear-gradient(90deg, #10b981, #059669);
    height: 100%;
    border-radius: 99px;
    transition: width 0.35s ease;
  }

  .bar-gemini {
    background: linear-gradient(90deg, #0ea5e9, #4f46e5);
    height: 100%;
    border-radius: 99px;
    transition: width 0.35s ease;
  }

  .bar-claude {
    background: var(--claude);
    height: 100%;
    border-radius: 99px;
    transition: width 0.35s ease;
  }

  .split-legend {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
  }

  .legend-item {
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }

  /* Tabs */
  .tabs {
    display: flex;
    gap: 16px;
    border-bottom: 1px solid var(--border);
    padding: 0 2px;
  }

  .tab-btn {
    background: none;
    border: none;
    color: var(--text-2);
    font-size: 12px;
    font-weight: 600;
    padding: 6px 2px 8px;
    cursor: pointer;
    position: relative;
    transition: color 0.15s;
  }

  .tab-btn:hover {
    color: var(--text);
  }

  .tab-btn.active {
    color: var(--text);
  }

  .tab-btn.active::after {
    content: "";
    position: absolute;
    left: 0;
    right: 0;
    bottom: -1px;
    height: 2px;
    border-radius: 2px;
    background: linear-gradient(90deg, #0ea5e9, #10b981);
  }

  /* List Rows */
  .list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .row-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 10px 12px;
    box-shadow: var(--shadow-sm);
    transition: border-color 0.15s, box-shadow 0.15s;
  }

  .row-card:hover {
    border-color: var(--border-strong);
    box-shadow: 0 3px 10px rgba(15, 23, 42, 0.06);
  }

  .row-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .row-left {
    display: flex;
    align-items: center;
    gap: 7px;
    min-width: 0;
    flex: 1;
  }

  .badge {
    font-size: 10px;
    font-weight: 700;
    padding: 2px 6px;
    border-radius: 5px;
    flex-shrink: 0;
    letter-spacing: 0.02em;
  }

  .badge.gpt {
    background: var(--gpt-soft);
    color: #059669;
  }

  .badge.gemini {
    background: var(--gemini-soft);
    color: #0284c7;
  }

  .badge.claude {
    background: var(--claude-soft);
    color: #6d28d9;
  }

  .model-name {
    font-size: 12px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .row-total {
    font-size: 13px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text);
    flex-shrink: 0;
  }

  .row-bar-track {
    height: 4px;
    background: #eef2f6;
    border-radius: 99px;
    margin: 7px 0 6px;
    overflow: hidden;
  }

  .row-bar-fill {
    height: 100%;
    border-radius: 99px;
  }

  .row-bar-fill.gpt { background: #10b981; }
  .row-bar-fill.gemini { background: #0ea5e9; }
  .row-bar-fill.claude { background: var(--claude); }

  .row-bottom {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 11px;
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
  }

  .tps-chip {
    color: #0284c7;
    font-weight: 600;
  }

  .mono {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 11px;
    color: #334155;
  }

  .req-meta {
    font-size: 11px;
    color: var(--text-2);
    margin-top: 4px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  .req-title {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 1;
    min-width: 0;
  }

  .req-metrics-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-top: 7px;
    padding-top: 6px;
    border-top: 1px solid var(--border);
    white-space: nowrap;
  }

  .req-metrics-text {
    font-size: 11px;
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
  }

  .req-metrics-text .sep {
    color: var(--text-3);
    margin: 0 4px;
  }

  .chip {
    font-size: 10px;
    font-variant-numeric: tabular-nums;
    padding: 1.5px 6px;
    border-radius: 5px;
    background: var(--bg);
    border: 1px solid var(--border);
    color: var(--text-2);
    flex-shrink: 0;
  }

  .chip.speed {
    background: rgba(14, 165, 233, 0.09);
    border-color: rgba(14, 165, 233, 0.22);
    color: #0284c7;
    font-weight: 600;
  }

  .empty {
    text-align: center;
    color: var(--text-3);
    padding: 32px 12px;
    font-size: 12px;
  }

  .login-item-status {
    padding: 4px 16px;
    color: var(--text-2);
    font-size: 11px;
  }

  /* Footer */
  .footer {
    padding: 9px 16px;
    border-top: 1px solid var(--border);
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 11px;
    color: var(--text-2);
    background: rgba(255, 255, 255, 0.85);
    backdrop-filter: blur(10px);
    flex-shrink: 0;
  }

  .footer-right {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  #updated-at, .toggle-label {
    white-space: nowrap;
  }

  .toggle-label {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    cursor: pointer;
    color: var(--text-2);
  }

  .toggle-label input {
    accent-color: #0284c7;
    cursor: pointer;
  }

  .mini-pills {
    display: inline-flex;
    background: rgba(15, 23, 42, 0.05);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 1.5px;
    gap: 1px;
  }

  .mini-pill {
    border: none;
    background: transparent;
    color: var(--text-2);
    font-size: 10px;
    font-weight: 500;
    padding: 2px 6px;
    border-radius: 4.5px;
    cursor: pointer;
    transition: all 0.12s ease;
  }

  .mini-pill.active {
    background: #ffffff;
    color: var(--text);
    font-weight: 600;
    box-shadow: 0 1px 2px rgba(15, 23, 42, 0.08);
  }

  .quit-btn {
    border: none;
    background: transparent;
    color: var(--text-2);
    font-size: 11px;
    cursor: pointer;
    padding: 2px 6px;
    border-radius: 5px;
  }

  .quit-btn:hover {
    background: rgba(239, 68, 68, 0.10);
    color: #dc2626;
  }
</style>
</head>
<body>
<div id="app" class="app">
  <div class="header">
    <div class="header-top">
      <div class="brand">
        <div class="brand-logo">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
            <path d="M2 12h4l2.5-6 4 12 3-7.5 1.8 1.5H22" stroke="#ffffff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
          </svg>
        </div>
        <span class="brand-name">TokenPulse</span>
        <span id="status-pill" class="status-pill"><span class="dot"></span><span id="status-text">空闲</span></span>
      </div>
      <div class="icon-actions">
        <button id="refresh-btn" class="icon-btn" title="立即刷新" onclick="postMsg('refresh')">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M21 12a9 9 0 1 1-2.64-6.36L21 8"/><path d="M21 3v5h-5"/>
          </svg>
        </button>
      </div>
    </div>

    <div class="filters">
      <div class="pill-group" id="time-pills">
        <button class="pill-btn active" data-val="today" onclick="postMsg('setTimeRange', 'today')">近1天</button>
        <button class="pill-btn" data-val="sevenDays" onclick="postMsg('setTimeRange', 'sevenDays')">7天</button>
        <button class="pill-btn" data-val="thirtyDays" onclick="postMsg('setTimeRange', 'thirtyDays')">30天</button>
        <button class="pill-btn" data-val="all" onclick="postMsg('setTimeRange', 'all')">全部</button>
      </div>
      <div class="pill-group" id="provider-pills">
        <button class="pill-btn active" data-val="all" onclick="postMsg('setProvider', 'all')">全部</button>
        <button class="pill-btn" data-val="gpt" onclick="postMsg('setProvider', 'gpt')">GPT</button>
        <button class="pill-btn" data-val="gemini" onclick="postMsg('setProvider', 'gemini')">Gemini</button>
        <button class="pill-btn" data-val="claude" onclick="postMsg('setProvider', 'claude')">Claude</button>
      </div>
    </div>
  </div>

  <div class="content">
    <div id="alert-box" class="alert-card" style="display:none;"></div>

    <div class="hero-grid">
      <div class="card">
        <div class="card-label"><span>总消耗 Token</span><span id="req-count">0 次</span></div>
        <div id="total-tokens" class="card-value">0</div>
        <div id="total-sub" class="card-sub">输入 0 · 输出 0</div>
        <div class="sparkline-wrap" id="token-bars"></div>
      </div>
      <div class="card">
        <div class="card-label"><span>平均生成速度</span><span id="latest-tps">最近 --</span></div>
        <div id="avg-tps" class="card-value accent-blue">--</div>
        <div class="sparkline-wrap" id="sparkline"></div>
      </div>
    </div>

    <div class="split-card">
      <div class="sub-stats">
        <div class="mini-stat">
          <span class="mini-label">输入 Token</span>
          <span id="input-tokens" class="mini-val">0</span>
        </div>
        <div class="mini-stat">
          <span class="mini-label">缓存命中</span>
          <span id="cache-rate" class="mini-val">--</span>
        </div>
        <div class="mini-stat">
          <span class="mini-label">输出 / 思考</span>
          <span id="output-tokens" class="mini-val">0</span>
        </div>
      </div>
      <div class="bar-track">
        <div id="bar-gpt" class="bar-gpt" style="width:0%"></div>
        <div id="bar-gemini" class="bar-gemini" style="width:0%"></div>
        <div id="bar-claude" class="bar-claude" style="width:0%"></div>
      </div>
      <div class="split-legend">
        <span class="legend-item"><span class="dot" style="background:#10b981;"></span>GPT <span id="legend-gpt">0</span></span>
        <span class="legend-item"><span class="dot" style="background:#38bdf8;"></span>Gemini <span id="legend-gemini">0</span></span>
        <span class="legend-item"><span class="dot" style="background:var(--claude);"></span>Claude <span id="legend-claude">0</span></span>
      </div>
      <div id="pricing" class="card-sub"></div>
    </div>

    <div class="tabs">
      <button class="tab-btn active" data-tab="models" onclick="switchTab('models')">模型排行</button>
      <button class="tab-btn" data-tab="sessions" onclick="switchTab('sessions')">活跃会话</button>
      <button class="tab-btn" data-tab="requests" onclick="switchTab('requests')">请求明细</button>
    </div>

    <div id="tab-content" class="list"></div>
  </div>

  <div class="login-item-status" id="login-item-status" role="status" hidden></div>
  <div class="footer">
    <span id="updated-at" title="每 2 秒自动检测">更新于 刚刚</span>
    <div class="footer-right">
      <label class="toggle-label">
        <input id="login-toggle" type="checkbox" onchange="postMsg('toggleLaunchAtLogin', this.checked)" />
        <span>开机自启</span>
      </label>
      <label class="toggle-label">
        <input id="sound-toggle" type="checkbox" onchange="postMsg('toggleSoundAlert', this.checked)" />
        <span>提示音</span>
      </label>
      <div class="mini-pills" id="menubar-mode-pills" title="状态栏右侧显示内容">
        <button class="mini-pill" data-val="none" onclick="postMsg('setMenuBarMode', 'none')">纯图标</button>
        <button class="mini-pill" data-val="tps" onclick="postMsg('setMenuBarMode', 'tps')">TPS</button>
        <button class="mini-pill" data-val="cost" onclick="postMsg('setMenuBarMode', 'cost')">金额</button>
      </div>
      <button class="quit-btn" onclick="postMsg('quit')">退出</button>
    </div>
  </div>
</div>

<script>
  let currentTab = 'models';
  let lastData = null;

  function postMsg(action, value) {
    if (action === 'refresh') {
      const btn = document.getElementById('refresh-btn');
      btn.classList.add('spinning');
      setTimeout(() => btn.classList.remove('spinning'), 650);
    }
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tokenPulse) {
      window.webkit.messageHandlers.tokenPulse.postMessage({ action, value: value === undefined ? null : value });
    }
  }

  function switchTab(tab) {
    currentTab = tab;
    document.querySelectorAll('.tab-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.tab === tab);
    });
    if (lastData) renderList(lastData);
  }

  function esc(str) {
    return String(str || '').replace(/[&<>"']/g, m => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[m]));
  }

  document.addEventListener('click', event => {
    const dismiss = event.target.closest('[data-dismiss-alert]');
    if (dismiss) {
      postMsg('dismissAlert', dismiss.dataset.dismissAlert);
      return;
    }
    const row = event.target.closest('[data-focus-app]');
    if (row) postMsg('focusApp', row.dataset.focusApp);
  });

  document.addEventListener('keydown', event => {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    if (!event.target.matches('[data-focus-app]')) return;
    event.preventDefault();
    postMsg('focusApp', event.target.dataset.focusApp);
  });

  let tokenBarsSignature;
  function renderTokenBars(bars) {
    const signature = JSON.stringify(bars);
    if (tokenBarsSignature === signature) return;
    tokenBarsSignature = signature;

    const container = document.getElementById('token-bars');
    if (!bars.length) {
      container.innerHTML = '<svg class="sparkline-svg" viewBox="0 0 160 30"><path d="M0 29h160" stroke="#e2e8f0" stroke-dasharray="3 3"/></svg><div class="spark-axis"><span>--</span><span>--</span></div>';
      return;
    }

    const width = 160;
    const height = 30;
    const slot = width / bars.length;
    const barWidth = Math.min(18, slot * 0.76);
    const maxTokens = Math.max(1, ...bars.map(bar => bar.tokensRaw));
    const rects = bars.map((bar, index) => {
      const barHeight = bar.tokensRaw > 0 ? Math.max(2, height * bar.tokensRaw / maxTokens) : 1;
      const x = index * slot + (slot - barWidth) / 2;
      return `<rect class="token-bar ${bar.tokensRaw > 0 ? '' : 'empty-bar'}" x="${x}" y="${height - barHeight}" width="${barWidth}" height="${barHeight}" rx="1.5"/>`;
    }).join('');
    const last = bars[bars.length - 1];
    container.innerHTML = `
      <div class="spark-tip"></div>
      <svg class="sparkline-svg" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" role="img" aria-label="Token 消耗趋势">${rects}</svg>
      <div class="spark-axis"><span>${esc(bars[0].label)}</span><span>${esc(last.endLabel)}</span></div>`;

    const svg = container.querySelector('svg');
    const nodes = svg.querySelectorAll('.token-bar');
    const tip = container.querySelector('.spark-tip');
    let highlighted = -1;
    svg.addEventListener('pointermove', event => {
      const rect = svg.getBoundingClientRect();
      const index = Math.max(0, Math.min(bars.length - 1, Math.floor((event.clientX - rect.left) / rect.width * bars.length)));
      if (index === highlighted) return;
      nodes[highlighted]?.classList.remove('highlighted');
      nodes[index].classList.add('highlighted');
      highlighted = index;
      const bar = bars[index];
      tip.innerHTML = `<div class="spark-tip-val">${esc(bar.tokensText)} Token</div><div class="spark-tip-sub">${esc(bar.period)} · ${bar.requests} 次请求</div>`;
      const center = (index + 0.5) * rect.width / bars.length;
      tip.style.left = Math.max(0, Math.min(rect.width - tip.offsetWidth, center - tip.offsetWidth / 2)) + 'px';
      tip.classList.add('visible');
    });
    svg.addEventListener('pointerleave', () => {
      nodes[highlighted]?.classList.remove('highlighted');
      highlighted = -1;
      tip.classList.remove('visible');
    });
  }

  const usd = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' });

  let sparkState = { points: [], coords: [], w: 160, h: 30, sig: '' };

  function renderSparkline(points) {
    const el = document.getElementById('sparkline');
    if (!points || points.length < 2) {
      sparkState.points = [];
      sparkState.sig = '';
      el.innerHTML = '<svg class="sparkline-svg" viewBox="0 0 160 30"><line x1="0" y1="22" x2="160" y2="22" stroke="rgba(15,23,42,0.12)" stroke-width="1.5" stroke-dasharray="3 3"/></svg><div class="spark-axis"><span>--</span><span>--</span></div>';
      return;
    }

    const sig = points.map(p => p.tps + '@' + p.fullTime).join('|');
    if (sig === sparkState.sig && el.querySelector('.spark-tip')) {
      return;
    }
    sparkState.sig = sig;
    sparkState.points = points;

    const vals = points.map(p => p.tps);
    const maxV = Math.max(...vals, 1);
    const minV = Math.min(...vals, 0);
    const span = Math.max(maxV - minV, 1);
    const w = 160, h = 30;
    const coords = points.map((p, i) => {
      const x = 3 + (i / (points.length - 1)) * (w - 6);
      const y = h - 4 - ((p.tps - minV) / span) * (h - 8);
      return { x, y };
    });
    sparkState.coords = coords;

    const linePath = 'M ' + coords.map(c => c.x.toFixed(1) + ' ' + c.y.toFixed(1)).join(' L ');
    const areaPath = linePath + ` L ${(w - 3).toFixed(1)} ${h} L 3 ${h} Z`;
    const firstTime = points[0].axisTime;
    const lastTime = points[points.length - 1].axisTime;
    const midHtml = points.length >= 6 ? `<span>${esc(points[Math.floor(points.length / 2)].axisTime)}</span>` : '';

    el.innerHTML = `
      <div class="spark-tip" id="spark-tip"></div>
      <svg class="sparkline-svg" id="spark-svg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
        <defs>
          <linearGradient id="sg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#0284c7" stop-opacity="0.22"/>
            <stop offset="100%" stop-color="#0284c7" stop-opacity="0"/>
          </linearGradient>
        </defs>
        <path d="${areaPath}" fill="url(#sg)"/>
        <path d="${linePath}" fill="none" stroke="#0284c7" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        <line id="spark-guide" x1="0" y1="2" x2="0" y2="${h - 2}" stroke="rgba(2,132,199,0.35)" stroke-width="1" stroke-dasharray="2 2" style="display:none;"/>
        <circle id="spark-dot" cx="0" cy="0" r="3" fill="#0284c7" stroke="#ffffff" stroke-width="1.4" style="display:none;"/>
      </svg>
      <div class="spark-axis"><span>${esc(firstTime)}</span>${midHtml}<span>${esc(lastTime)}</span></div>`;

    el.onmousemove = function(e) {
      if (!sparkState.points.length) return;
      const rect = el.getBoundingClientRect();
      const relX = Math.max(0, Math.min(1, (e.clientX - rect.left) / Math.max(rect.width, 1)));
      const idx = Math.round(relX * (sparkState.points.length - 1));
      const pt = sparkState.points[idx];
      const coord = sparkState.coords[idx];
      const guide = document.getElementById('spark-guide');
      const dot = document.getElementById('spark-dot');
      const tip = document.getElementById('spark-tip');
      if (!guide || !dot || !tip) return;

      guide.setAttribute('x1', coord.x.toFixed(1));
      guide.setAttribute('x2', coord.x.toFixed(1));
      guide.style.display = '';
      dot.setAttribute('cx', coord.x.toFixed(1));
      dot.setAttribute('cy', coord.y.toFixed(1));
      dot.style.display = '';

      tip.innerHTML = `<div class="spark-tip-val">${esc(pt.tpsText)}</div><div class="spark-tip-sub">${esc(pt.fullTime)} · ${esc(pt.model)}</div>`;
      tip.classList.add('visible');

      const tipW = tip.offsetWidth || 110;
      const anchorX = (coord.x / w) * rect.width;
      const clampedLeft = Math.max(-10, Math.min(rect.width - tipW + 6, anchorX - tipW / 2));
      tip.style.left = clampedLeft + 'px';
    };

    el.onmouseleave = function() {
      const guide = document.getElementById('spark-guide');
      const dot = document.getElementById('spark-dot');
      const tip = document.getElementById('spark-tip');
      if (guide) guide.style.display = 'none';
      if (dot) dot.style.display = 'none';
      if (tip) tip.classList.remove('visible');
    };
  }

  function renderList(d) {
    const container = document.getElementById('tab-content');
    if (currentTab === 'models') {
      if (!d.models || d.models.length === 0) {
        container.innerHTML = '<div class="empty">当前时间范围内暂无 GPT / Gemini 请求记录</div>';
        return;
      }
      const maxTokens = Math.max(...d.models.map(m => m.totalTokensRaw), 1);
      container.innerHTML = d.models.map(m => {
        const cls = m.provider.toLowerCase();
        const pct = Math.max(4, Math.round((m.totalTokensRaw / maxTokens) * 100));
        return `
          <div class="row-card">
            <div class="row-top">
              <div class="row-left">
                <span class="badge ${cls}">${esc(m.provider)}</span>
                <span class="model-name">${esc(m.model)}</span>
              </div>
              <span class="row-total">${esc(m.totalTokens)}</span>
            </div>
            <div class="row-bar-track"><div class="row-bar-fill ${cls}" style="width:${pct}%"></div></div>
            <div class="row-bottom">
              <span>输入 ${esc(m.inputTokens)} · 输出 ${esc(m.outputTokens)}${m.cachedTokens !== '0' ? ' · 缓存 ' + esc(m.cachedTokens) : ''}</span>
              <span class="tps-chip">${m.requestCount} 次 · ${esc(m.avgTPS)}</span>
            </div>
          </div>`;
      }).join('');
    } else if (currentTab === 'sessions') {
      if (!d.sessions || d.sessions.length === 0) {
        container.innerHTML = '<div class="empty">暂无检测到本地活跃会话</div>';
        return;
      }
      container.innerHTML = d.sessions.map(s => {
        const cls = s.provider.toLowerCase();
        const providerColor = cls === 'gpt' ? '#10b981' : (cls === 'claude' ? '#8b5cf6' : '#0284c7');
        const stateColor = s.stateType === 'needsAction' ? '#d97706' : (s.stateType === 'running' ? providerColor : '#94a3b8');
        const pulseCls = s.stateType !== 'idle' ? 'pulse' : '';
        return `
          <div class="row-card" role="button" tabindex="0" data-focus-app="${esc(s.sourceApp)}" title="切换到 ${esc(s.sourceApp)}">
            <div class="row-top">
              <div class="row-left">
                <span class="dot ${pulseCls}" style="background:${providerColor};flex-shrink:0;"></span>
                <span class="badge ${cls}">${esc(s.provider)}</span>
                <span class="model-name">${esc(s.title)}</span>
              </div>
              <span class="row-total">${esc(s.totalTokens)}</span>
            </div>
            <div class="row-bottom" style="margin-top:6px;">
              <span>${esc(s.model)} · <span style="color:${stateColor};font-weight:600;">${esc(s.stateLabel)}</span> · ${esc(s.updatedAt)}</span>
              <span class="tps-chip">${esc(s.latestTPS)}</span>
            </div>
          </div>`;
      }).join('');
    } else {
      if (!d.requests || d.requests.length === 0) {
        container.innerHTML = '<div class="empty">暂无请求明细</div>';
        return;
      }
      container.innerHTML = d.requests.map(r => {
        const cls = r.provider.toLowerCase();
        const parts = [`输入 ${esc(r.inputTokens)}`, `输出 ${esc(r.outputTokens)}`];
        if (r.cachedTokens !== '0') parts.push(`缓存 ${r.cachePct}%`);
        if (r.reasoningTokens !== '0') parts.push(`思考 ${esc(r.reasoningTokens)}`);
        if (r.duration !== '--') parts.push(`${esc(r.duration)}`);
        return `
          <div class="row-card">
            <div class="row-top">
              <div class="row-left">
                <span class="badge ${cls}">${esc(r.provider)}</span>
                <span class="model-name">${esc(r.model)}</span>
              </div>
              <span class="row-total">${esc(r.totalTokens)}</span>
            </div>
            <div class="req-meta">
              <span class="req-title">${esc(r.sessionTitle)} · ${esc(r.sourceApp)}</span>
              <span class="mono" style="color:var(--text-3);flex-shrink:0;">${esc(r.exactTime)}</span>
            </div>
            <div class="req-metrics-row">
              <span class="req-metrics-text">${parts.join('<span class="sep">·</span>')}</span>
              <span class="chip speed">${esc(r.tps)}</span>
            </div>
          </div>`;
      }).join('');
    }
  }

  window.renderTokenPulse = function(d) {
    lastData = d;
    const appEl = document.getElementById('app');
    appEl.classList.toggle('state-needs-action', d.overallState === 'needsAction');

    const pill = document.getElementById('status-pill');
    const dot = pill.querySelector('.dot');
    pill.className = 'status-pill ' + (d.overallState === 'needsAction' ? 'needs-action' : (d.overallState === 'running' ? 'running' : ''));
    dot.className = 'dot ' + (d.overallState !== 'idle' ? 'pulse' : '');
    document.getElementById('status-text').textContent = d.statusText;

    document.querySelectorAll('#time-pills .pill-btn').forEach(b => b.classList.toggle('active', b.dataset.val === d.timeRange));
    document.querySelectorAll('#provider-pills .pill-btn').forEach(b => b.classList.toggle('active', b.dataset.val === d.providerFilter));

    const alertBox = document.getElementById('alert-box');
    if (d.alerts && d.alerts.length > 0) {
      alertBox.style.display = 'flex';
      alertBox.innerHTML = `
        <div class="alert-header">
          <span>需要你操作</span>
          <span>${d.alerts.length} 项</span>
        </div>
      ` + d.alerts.map(a => `
        <div class="alert-item" data-focus-app="${esc(a.sourceApp)}" title="切换到 ${esc(a.sourceApp)}">
          <span class="badge ${a.provider.toLowerCase()}">${esc(a.provider)}</span>
          <div class="alert-meta" role="button" tabindex="0" data-focus-app="${esc(a.sourceApp)}">
            <div class="alert-title">${esc(a.title)}</div>
            <div class="alert-sub">${esc(a.sourceApp)} · ${esc(a.reason)}</div>
          </div>
          <button class="dismiss-btn" data-dismiss-alert="${esc(a.id)}">忽略</button>
        </div>
      `).join('');
    } else {
      alertBox.style.display = 'none';
    }

    document.getElementById('total-tokens').textContent = d.totalTokens;
    document.getElementById('req-count').textContent = d.requestCount + ' 次';
    document.getElementById('total-sub').textContent = `输入 ${d.inputTokens} · 输出 ${d.outputTokens}`;
    document.getElementById('avg-tps').textContent = d.avgTPS;
    document.getElementById('latest-tps').textContent = '最近 ' + d.latestTPS;
    renderSparkline(d.tpsPoints);
    renderTokenBars(d.tokenBars);

    const pricing = document.getElementById('pricing');
    const missingPrices = d.requestCount - d.pricedRequests;
    const cost = d.pricedRequests || !missingPrices ? '~' + usd.format(d.estimatedCostUSD) : '—';
    const savings = d.pricedRequests || !missingPrices ? '~' + usd.format(d.cacheSavedUSD) : '—';
    pricing.textContent = `等效 ${cost} · 缓存省 ${savings}${missingPrices && d.pricedRequests ? ' *' : ''}`;
    pricing.title = missingPrices ? `${missingPrices} 次请求的模型暂无参考费率` : '按参考费率估算（美元）';

    document.getElementById('input-tokens').textContent = d.inputTokens;
    document.getElementById('cache-rate').textContent = d.cacheRate;
    document.getElementById('output-tokens').textContent = d.reasoningTokens !== '0' ? `${d.outputTokens} (${d.reasoningTokens})` : d.outputTokens;

    for (const provider of ['gpt', 'gemini', 'claude']) {
      document.getElementById('bar-' + provider).style.width = d[provider + 'Percent'] + '%';
      document.getElementById('legend-' + provider).textContent = d[provider + 'Tokens'];
    }

    document.getElementById('updated-at').textContent = '更新于 ' + d.updatedAt;
    document.querySelectorAll('#menubar-mode-pills .mini-pill').forEach(b => {
      b.classList.toggle('active', b.dataset.val === d.menuBarDisplayMode);
    });
    document.getElementById('sound-toggle').checked = !!d.soundAlertEnabled;
    const login = document.getElementById('login-toggle');
    login.checked = d.launchAtLogin || d.launchAtLoginNeedsApproval;
    login.indeterminate = d.launchAtLoginNeedsApproval;
    const loginStatus = document.getElementById('login-item-status');
    const loginMessage = d.loginItemError || (d.launchAtLoginNeedsApproval ? '请在系统设置的「登录项」中允许 TokenPulse。' : '');
    loginStatus.hidden = !loginMessage;
    if (loginStatus.textContent !== loginMessage) loginStatus.textContent = loginMessage;

    renderList(d);
  };
</script>
</body>
</html>
"""
}
