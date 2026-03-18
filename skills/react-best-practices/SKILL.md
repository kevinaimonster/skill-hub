---
name: react-best-practices
description: |
  React宝典——React 与 Next.js 全栈最佳实践指南。
  当用户编写、审查或重构 React/Next.js 代码时自动激活。
  触发场景：React 最佳实践、React 怎么写、组件设计、hooks 用法、hooks 怎么用、
  状态管理、性能优化、React 性能、Server Components、RSC、Next.js 集成、
  数据获取、bundle 优化、重渲染优化、React 19 新特性、use hook、
  React best practices、component design patterns、React performance、
  how to write React、Next.js best practices、React Server Components。
  覆盖：组件设计模式、Hooks 最佳实践、状态管理策略、性能优化、
  Server Components、Next.js 15+ 集成、React 19+ 新 API。
license: MIT
version: "1.0.0"
user-invocable: true
---

# React宝典

React 与 Next.js 全栈最佳实践指南（React 19+ / Next.js 15+），面向 2025-2026 生态。包含 8 大类别、60+ 条规则，按影响等级排序，适用于编写新组件、代码审查、性能优化和重构场景。

---

## 适用时机

在以下场景中使用本指南：

- 编写新的 React 组件或页面
- 实现数据获取逻辑
- 审查代码性能问题
- 重构已有代码
- 优化 bundle 大小和加载时间
- 迁移到 React 19+ / Next.js 15+ / Server Components

---

## 一、消除请求瀑布（CRITICAL）

请求瀑布是性能的头号杀手。多个异步操作串行执行时，总延迟 = 所有操作之和。

### 1.1 延迟 await 到真正需要的位置

```typescript
// ❌ 阻塞整个函数
async function Page() {
  const user = await getUser();
  const posts = await getPosts(); // 必须等 getUser 完成
  return <Feed user={user} posts={posts} />;
}

// ✅ 并行发起，延迟 await
async function Page() {
  const userPromise = getUser();
  const postsPromise = getPosts();
  const [user, posts] = await Promise.all([userPromise, postsPromise]);
  return <Feed user={user} posts={posts} />;
}
```

### 1.2 用 Promise.all() 并行化独立操作

当多个异步操作互不依赖时，始终使用 `Promise.all()` 并行执行。

```typescript
// ❌ 串行：总时间 = T1 + T2 + T3
const user = await fetchUser(id);
const orders = await fetchOrders(id);
const recommendations = await fetchRecommendations(id);

// ✅ 并行：总时间 = max(T1, T2, T3)
const [user, orders, recommendations] = await Promise.all([
  fetchUser(id),
  fetchOrders(id),
  fetchRecommendations(id),
]);
```

### 1.3 策略性放置 Suspense 边界

用 Suspense 拆分页面，让快的部分先展示，慢的部分异步加载。

```tsx
// ✅ 外壳立即可见，数据部分逐步流式加载
export default function DashboardPage() {
  return (
    <DashboardShell>
      <Suspense fallback={<StatsSkeleton />}>
        <StatsPanel />
      </Suspense>
      <Suspense fallback={<FeedSkeleton />}>
        <ActivityFeed />
      </Suspense>
    </DashboardShell>
  );
}
```

### 1.4 API Route 中避免瀑布链

在 API Route / Server Action 中同样适用——先发起所有请求，再 await。

### 1.5 有依赖关系时最大化并行度

当操作之间存在部分依赖时，用依赖图分析哪些可以并行。

```typescript
// ✅ user 和 config 并行；posts 依赖 user，但 config 不阻塞它
const [user, config] = await Promise.all([getUser(), getConfig()]);
const posts = await getPosts(user.id);
```

---

## 二、Bundle 体积优化（CRITICAL）

### 2.1 避免 Barrel File 导入

Barrel file（`index.ts` 聚合导出）会导致 tree-shaking 失效，一个图标可能拉入整个图标库。

```typescript
// ❌ 拉入全部图标（200KB+）
import { Check } from "lucide-react";

// ✅ 直接从源文件导入
import Check from "lucide-react/dist/esm/icons/check";
```

适用于所有 icon 库、UI 组件库、工具库。

### 2.2 动态导入重型组件

对大型组件（编辑器、图表、地图等）使用 `next/dynamic` 或 `React.lazy`。

```typescript
// ✅ Monaco Editor (~300KB) 仅在需要时加载
import dynamic from "next/dynamic";

const CodeEditor = dynamic(() => import("@/components/CodeEditor"), {
  loading: () => <EditorSkeleton />,
  ssr: false,
});
```

### 2.3 延迟加载非关键第三方库

分析脚本、错误追踪等不应阻塞首屏。

```typescript
// ✅ hydration 完成后再加载分析脚本
useEffect(() => {
  import("@analytics/core").then((mod) => mod.init());
}, []);
```

### 2.4 条件加载模块

仅在功能激活时才加载对应的模块/数据。

### 2.5 基于用户意图预加载

在 hover/focus 时预加载即将使用的组件。

```tsx
// ✅ hover 时预加载，点击时立即可用
<button
  onMouseEnter={() => import("@/components/SettingsPanel")}
  onClick={() => setShowSettings(true)}
>
  设置
</button>
```

---

## 三、服务端性能（HIGH）

### 3.1 Server Action 必须验证身份

Server Action 是公开端点，必须像 API Route 一样验证认证和授权。

```typescript
"use server";

export async function deletePost(postId: string) {
  const session = await auth(); // ✅ 始终验证
  if (!session) throw new Error("Unauthorized");
  if (!await canDelete(session.user.id, postId)) throw new Error("Forbidden");
  await db.post.delete({ where: { id: postId } });
}
```

### 3.2 最小化 RSC 边界的序列化

Server Component 传给 Client Component 的每个 prop 都会被序列化进 HTML。只传客户端需要的字段。

```typescript
// ❌ 传了整个 user 对象（包含敏感字段）
<UserCard user={user} />

// ✅ 只传需要的字段
<UserCard name={user.name} avatar={user.avatar} />
```

### 3.3 用 React.cache() 做请求内去重

同一次请求中多个组件调用同一个数据函数时，用 `React.cache()` 避免重复执行。

```typescript
import { cache } from "react";

export const getUser = cache(async (id: string) => {
  return db.user.findUnique({ where: { id } });
});

// 同一请求中多次调用 getUser(id) 只执行一次
```

### 3.4 跨请求使用 LRU 缓存

`React.cache()` 仅在单次请求内生效。对跨请求共享的数据，使用 LRU 缓存。

```typescript
import { LRUCache } from "lru-cache";

const cache = new LRUCache<string, any>({ max: 500, ttl: 1000 * 60 * 5 });

export async function getConfig() {
  const cached = cache.get("config");
  if (cached) return cached;
  const config = await db.config.findFirst();
  cache.set("config", config);
  return config;
}
```

### 3.5 静态 I/O 提升到模块级别

字体文件、Logo、静态配置等不要每次请求都读取。

```typescript
// ✅ 模块加载时读取一次
const logoBuffer = await fs.readFile("./public/logo.png");

export function Logo() {
  return <img src={`data:image/png;base64,${logoBuffer.toString("base64")}`} />;
}
```

### 3.6 用 after() 做非阻塞操作

日志、埋点等不影响响应的操作用 `after()` 推迟到响应发送之后。

```typescript
import { after } from "next/server";

export async function POST(request: Request) {
  const result = await processOrder(request);

  after(async () => {
    await logAnalytics({ event: "order_created", orderId: result.id });
  });

  return Response.json(result);
}
```

### 3.7 并行数据获取 + 组件组合

利用 Server Component 的组合特性，让独立的数据获取自动并行。

### 3.8 避免重复序列化

不要同时传原始数组和衍生状态，让客户端自行计算。

---

## 四、客户端数据获取（MEDIUM-HIGH）

### 4.1 用 SWR/TanStack Query 自动去重

多个组件实例订阅同一数据时自动共享请求。

```typescript
// ✅ 多个组件调用同一 key，只发一次请求
function useUser(id: string) {
  return useSWR(`/api/users/${id}`, fetcher);
}
```

### 4.2 全局事件监听器去重

用 `useSyncExternalStore` 或 `useSWRSubscription` 共享 WebSocket/事件源。

### 4.3 使用 Passive Event Listener

滚动、触摸事件加 `{ passive: true }`，消除浏览器滚动延迟。

```typescript
// ✅ 不阻塞滚动
element.addEventListener("touchstart", handler, { passive: true });
```

### 4.4 localStorage 加版本号并最小化存储

```typescript
// ✅ 带版本前缀 + 只存必要字段 + try-catch 包裹
const STORAGE_KEY = "app_prefs_v2";

function savePrefs(prefs: UserPrefs) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      theme: prefs.theme,
      lang: prefs.lang,
    }));
  } catch (e) {
    // 存储已满或隐私模式
  }
}
```

---

## 五、重渲染优化（MEDIUM）

### 5.1 渲染期间计算派生状态

不要把可以计算的值存进 state——直接在渲染中计算。

```typescript
// ❌ 多余的 state + effect
const [items, setItems] = useState(data);
const [filteredItems, setFilteredItems] = useState([]);
useEffect(() => {
  setFilteredItems(items.filter((i) => i.active));
}, [items]);

// ✅ 渲染期间直接计算
const [items, setItems] = useState(data);
const filteredItems = items.filter((i) => i.active);
```

### 5.2 不要在组件内定义组件

内联组件每次父组件渲染都会导致完全卸载+重新挂载。

```typescript
// ❌ 每次渲染都创建新组件
function Parent() {
  function Child() { return <div>child</div>; } // 别这样做
  return <Child />;
}

// ✅ 提取到外部，用 props 传递数据
function Child({ data }: { data: string }) {
  return <div>{data}</div>;
}
function Parent() {
  return <Child data="hello" />;
}
```

### 5.3 用 useRef 存储不触发渲染的频繁变化值

鼠标位置、滚动进度、计时器 ID 等不需要触发 UI 更新的值，用 ref 而非 state。

### 5.4 用 useMemo/React.memo 控制子组件渲染

但注意：**简单表达式不要包 useMemo**。`useMemo` 本身有开销，布尔值/数字/字符串的简单计算不值得 memo。

```typescript
// ❌ 过度 memo
const isActive = useMemo(() => status === "active", [status]);

// ✅ 直接计算
const isActive = status === "active";
```

### 5.5 用函数式 setState 避免闭包陷阱

```typescript
// ❌ 可能使用过期的 count
setCount(count + 1);

// ✅ 始终基于最新值
setCount((prev) => prev + 1);
```

### 5.6 useState 惰性初始化

传函数给 `useState`，仅在首次渲染时执行。

```typescript
// ❌ 每次渲染都执行 expensive()
const [data, setData] = useState(expensiveComputation());

// ✅ 只在挂载时执行一次
const [data, setData] = useState(() => expensiveComputation());
```

### 5.7 提取非原始值默认值为常量

```typescript
// ❌ 每次渲染新建对象，memo 失效
function List({ config = { pageSize: 10 } }) { ... }

// ✅ 稳定引用
const DEFAULT_CONFIG = { pageSize: 10 };
function List({ config = DEFAULT_CONFIG }) { ... }
```

### 5.8 缩窄 Effect 依赖

订阅派生的布尔值而非连续变化的值。

```typescript
// ❌ value 每次变化都触发 effect
useEffect(() => { ... }, [value]);

// ✅ 只在 isAboveThreshold 变化时触发
const isAboveThreshold = value > 100;
useEffect(() => { ... }, [isAboveThreshold]);
```

### 5.9 把交互逻辑放进事件处理器

用户行为 -> 事件处理器，不是 state + effect 间接表达。

### 5.10 延迟读取动态状态

如果只在回调中读取 searchParams/localStorage，不要在渲染层订阅它们。

### 5.11 用 startTransition 标记非紧急更新

```typescript
// ✅ 搜索输入立即响应，结果列表延迟更新
function Search() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);

  function handleChange(e: React.ChangeEvent<HTMLInputElement>) {
    setQuery(e.target.value);
    startTransition(() => {
      setResults(searchItems(e.target.value));
    });
  }

  return (
    <>
      <input value={query} onChange={handleChange} />
      <ResultList results={results} />
    </>
  );
}
```

### 5.12 提取为 Memo 组件实现提前返回

### 5.13 Effect 内不该做的事 -> 移到事件处理器

---

## 六、渲染性能（MEDIUM）

### 6.1 用 CSS content-visibility 优化长列表

```css
/* ✅ 浏览器跳过屏幕外内容的渲染 */
.list-item {
  content-visibility: auto;
  contain-intrinsic-size: 0 80px;
}
```

### 6.2 静态 JSX 提升到组件外部

不会变化的 JSX 片段提取为模块级常量，避免每次渲染重新创建。

```typescript
// ✅ 只创建一次
const EMPTY_STATE = <div className="empty">暂无数据</div>;

function List({ items }: { items: Item[] }) {
  if (items.length === 0) return EMPTY_STATE;
  return <ul>{items.map(...)}</ul>;
}
```

### 6.3 防止 Hydration 闪烁

依赖 localStorage/cookie 的 UI（如暗色模式）用同步脚本在 React hydrate 之前设置。

```html
<!-- ✅ 在 <head> 中同步执行，hydration 前完成 -->
<script>
  const theme = localStorage.getItem("theme") || "light";
  document.documentElement.dataset.theme = theme;
</script>
```

### 6.4 使用 Activity 组件（React 19+）

频繁切换显示/隐藏的重型组件，用 `<Activity>` 保留 state 和 DOM。

```tsx
// ✅ 切换时保留状态，不重新挂载
import { Activity } from "react";

<Activity mode={activeTab === "editor" ? "visible" : "hidden"}>
  <HeavyEditor />
</Activity>
```

### 6.5 SVG 动画包裹 div

直接在 SVG 元素上做 CSS 动画会跳过 GPU 加速。包一层 div。

### 6.6 优化 SVG 精度

用 SVGO 将坐标精度降到 1 位小数，减少 SVG 体积 20-40%。

### 6.7 script 标签始终加 defer/async

### 6.8 用 useTransition 替代手动 loading state

```typescript
// ❌ 手动管理 loading
const [isLoading, setIsLoading] = useState(false);
async function handleClick() {
  setIsLoading(true);
  await doSomething();
  setIsLoading(false);
}

// ✅ 内置 isPending
const [isPending, startTransition] = useTransition();
function handleClick() {
  startTransition(async () => {
    await doSomething();
  });
}
```

### 6.9 用显式三元替代 && 渲染

```tsx
// ❌ count 为 0 时渲染 "0" 而非 null
{count && <Badge count={count} />}

// ✅ 明确处理 falsy 值
{count > 0 ? <Badge count={count} /> : null}
```

### 6.10 使用 React DOM 资源提示

```typescript
import { prefetchDNS, preconnect, preload } from "react-dom";

// ✅ 预连接关键第三方域
preconnect("https://api.example.com");
preload("/fonts/inter.woff2", { as: "font", type: "font/woff2" });
```

### 6.11 suppressHydrationWarning 用于已知差异

日期、随机 ID 等已知的 SSR/客户端差异，使用 `suppressHydrationWarning`。

---

## 七、JavaScript 性能（LOW-MEDIUM）

### 7.1 避免布局抖动

批量写入样式，再读取布局属性。交错读写会强制同步 reflow。

```typescript
// ❌ 每次循环都触发 reflow
elements.forEach((el) => {
  el.style.width = `${container.offsetWidth}px`; // 读 -> 写 -> 读 -> 写
});

// ✅ 先读，再批量写
const width = container.offsetWidth;
elements.forEach((el) => {
  el.style.width = `${width}px`;
});
```

### 7.2 用 Map/Set 替代数组查找

O(1) vs O(n) 的差距在大数据集下指数级放大。

```typescript
// ❌ O(n) 查找
const user = users.find((u) => u.id === targetId);

// ✅ O(1) 查找
const userMap = new Map(users.map((u) => [u.id, u]));
const user = userMap.get(targetId);
```

### 7.3 循环中缓存属性访问

### 7.4 缓存重复函数调用结果

### 7.5 缓存 Storage API 调用

localStorage/sessionStorage 是同步阻塞的，用内存缓存避免重复读取。

### 7.6 合并多次数组迭代

```typescript
// ❌ 两次迭代
const active = users.filter((u) => u.active).map((u) => u.name);

// ✅ 一次迭代
const active = users.reduce<string[]>((acc, u) => {
  if (u.active) acc.push(u.name);
  return acc;
}, []);

// ✅ 或用 flatMap
const active = users.flatMap((u) => (u.active ? [u.name] : []));
```

### 7.7 先检查长度再比较数组

### 7.8 函数提前返回

确定结果后立即 return，不要走完所有分支。

### 7.9 正则表达式提升到模块级

```typescript
// ❌ 每次渲染都编译正则
function validate(email: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

// ✅ 模块级编译一次
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function validate(email: string) {
  return EMAIL_RE.test(email);
}
```

### 7.10 用 flatMap 替代 filter + map

### 7.11 求最值用循环而非排序

O(n) vs O(n log n)。

### 7.12 用 toSorted() 替代 sort()

`toSorted()` 返回新数组，不会 mutate 原数组，避免 React state 变异 bug。

### 7.13 提前退出循环

---

## 八、高级模式（LOW）

### 8.1 模块级初始化而非 useEffect

```typescript
// ❌ StrictMode 下执行两次，组件重新挂载时再次执行
useEffect(() => {
  analytics.init();
}, []);

// ✅ 模块级，只执行一次
let initialized = false;
function initOnce() {
  if (initialized) return;
  initialized = true;
  analytics.init();
}
initOnce();
```

### 8.2 用 Ref 存储事件处理器

保持稳定的订阅引用，避免回调变化时反复重新订阅。

```typescript
const handlerRef = useRef(onMessage);
handlerRef.current = onMessage; // 每次渲染更新引用

useEffect(() => {
  const handler = (e: MessageEvent) => handlerRef.current(e.data);
  ws.addEventListener("message", handler);
  return () => ws.removeEventListener("message", handler);
}, []); // 依赖数组为空——永不重新订阅
```

### 8.3 useEffectEvent（React 19+）

在回调中访问最新值，而不触发 Effect 重新执行。

```typescript
// ✅ React 19+ 实验 API
const onTick = useEffectEvent((time: number) => {
  console.log(latestConfig, time); // 始终拿到最新 config
});

useEffect(() => {
  const id = setInterval(() => onTick(Date.now()), 1000);
  return () => clearInterval(id);
}, []); // 不需要依赖 config
```

---

## 九、React 19+ 新特性速查

React 19 引入了多个范式级变更，以下是关键新 API：

### 9.1 use() Hook

在组件中直接读取 Promise 和 Context，替代部分 useEffect + useState 模式。

```typescript
// ✅ React 19: 直接在组件中 unwrap Promise
import { use } from "react";

function UserProfile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise); // 配合 Suspense 使用
  return <div>{user.name}</div>;
}
```

### 9.2 Actions（useActionState + useFormStatus）

表单提交的一等公民支持。

```typescript
"use client";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

function SubmitButton() {
  const { pending } = useFormStatus();
  return <button disabled={pending}>{pending ? "提交中..." : "提交"}</button>;
}

function LoginForm() {
  const [state, formAction] = useActionState(loginAction, { error: null });

  return (
    <form action={formAction}>
      <input name="email" type="email" required />
      {state.error && <p className="error">{state.error}</p>}
      <SubmitButton />
    </form>
  );
}
```

### 9.3 useOptimistic

乐观更新，提升交互感知速度。

```typescript
const [optimisticMessages, addOptimistic] = useOptimistic(
  messages,
  (state, newMsg: string) => [...state, { text: newMsg, sending: true }]
);

async function sendMessage(text: string) {
  addOptimistic(text); // 立即显示
  await submitMessage(text); // 后台提交
}
```

### 9.4 ref 作为 prop 直接传递

React 19 中函数组件直接接收 ref 作为 prop，不再需要 `forwardRef`。

```typescript
// ✅ React 19: 直接传递
function Input({ ref, ...props }: { ref: React.Ref<HTMLInputElement> }) {
  return <input ref={ref} {...props} />;
}
```

### 9.5 文档元数据原生支持

```tsx
// ✅ React 19: 组件内直接声明 <title>、<meta>、<link>
function BlogPost({ post }: { post: Post }) {
  return (
    <article>
      <title>{post.title}</title>
      <meta name="description" content={post.excerpt} />
      <h1>{post.title}</h1>
      <p>{post.content}</p>
    </article>
  );
}
```

---

## 十、Server Components 与 Next.js 15+ 实战

### 10.1 组件划分原则

```
Server Component（默认）    Client Component（'use client'）
─────────────────────────   ─────────────────────────────
数据获取                     事件处理（onClick 等）
敏感逻辑/密钥访问            useState / useEffect / useRef
数据库直连                   浏览器 API（localStorage 等）
静态渲染                     第三方仅客户端库
大型依赖（不发送到客户端）     实时交互组件
```

### 10.2 组合模式：Server 包 Client

```tsx
// ✅ Server Component 获取数据，Client Component 处理交互
// app/dashboard/page.tsx (Server Component)
export default async function DashboardPage() {
  const stats = await getStats(); // 服务端直连数据库

  return (
    <div>
      <h1>仪表盘</h1>
      <StatsDisplay initialData={stats} /> {/* Client Component */}
    </div>
  );
}

// components/StatsDisplay.tsx
"use client";
export function StatsDisplay({ initialData }: { initialData: Stats }) {
  const [data, setData] = useState(initialData);
  // 客户端交互逻辑...
}
```

### 10.3 Next.js 15+ 缓存策略

```typescript
// 静态缓存（构建时）
fetch(url, { cache: "force-cache" });

// 按时间重新验证
fetch(url, { next: { revalidate: 3600 } });

// 动态不缓存
fetch(url, { cache: "no-store" });

// 按需重新验证
import { revalidateTag, revalidatePath } from "next/cache";
revalidateTag("posts");
revalidatePath("/blog");
```

### 10.4 Partial Prerendering（PPR）

Next.js 15+ 的混合渲染模式，静态外壳 + 动态内容流式加载。

```tsx
// next.config.ts
export default { experimental: { ppr: true } };

// 页面中：静态部分预渲染，Suspense 内动态流式加载
export default function ProductPage({ params }: { params: { id: string } }) {
  return (
    <ProductLayout>
      {/* 这部分是静态的，预渲染到 HTML */}
      <ProductHeader id={params.id} />
      <Suspense fallback={<PriceSkeleton />}>
        {/* 这部分是动态的，流式加载 */}
        <DynamicPrice id={params.id} />
      </Suspense>
    </ProductLayout>
  );
}
```

### 10.5 Server Actions 最佳实践

```typescript
"use server";

import { z } from "zod";
import { revalidatePath } from "next/cache";

const CreatePostSchema = z.object({
  title: z.string().min(1).max(200),
  content: z.string().min(1),
});

export async function createPost(formData: FormData) {
  // 1. 验证身份
  const session = await auth();
  if (!session) throw new Error("Unauthorized");

  // 2. 验证输入
  const parsed = CreatePostSchema.safeParse({
    title: formData.get("title"),
    content: formData.get("content"),
  });
  if (!parsed.success) return { error: parsed.error.flatten() };

  // 3. 执行操作
  await db.post.create({ data: { ...parsed.data, authorId: session.user.id } });

  // 4. 更新缓存
  revalidatePath("/posts");
  return { success: true };
}
```

---

## 能力边界声明

当用户的需求涉及以下方面时，**简要提醒一次**，然后聚焦回 React 代码最佳实践：

| 需求 | 建议 |
|------|------|
| UI 美化 / 视觉设计 / 页面太丑 | 推荐使用 **frontend-design** 技能（`/frontend-design`），专精于界面视觉优化 |
| CSS 动效设计 / 微交互 | 推荐使用 **frontend-design** 技能处理视觉层面，本技能聚焦于 React 代码模式 |

提醒方式示例：*"UI 美化推荐试试 `/frontend-design` 技能，它专门处理视觉设计。我这边聚焦帮你把 React 代码写对写好。"*

**只在首次遇到时提醒一次，不要反复提及。**
