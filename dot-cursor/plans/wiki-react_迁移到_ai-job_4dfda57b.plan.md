---
name: wiki-react 迁移到 ai-job
overview: 把 wiki-react 的 4 个页面（相机 / 图片识别 / 详情 / 历史）作为 ai-job 页面的 toolsType=wiki 分支嵌入，使用项目统一的 appRequest 替换自带 fetch，用内部 state 机做 4 个视图切换（不引入 react-router-dom），完成后删除 wiki-react/ 目录。
todos:
  - id: deps
    content: 在 package.json 添加 ali-oss 和 @types/ali-oss（npm install）
    status: completed
  - id: assets
    content: 把 wiki-react/public/assets/*.webp + public_load_miaobi.gif 拷到 src/assets/images/wiki/
    status: completed
  - id: types
    content: 新建 src/pages/ai-job/components/Wiki/types.ts，拷入 wiki-react 原 types/index.ts
    status: completed
  - id: api
    content: 新建 Wiki/api.ts，用 appRequest + BASE_URL 改写 7 个接口（get/voice、oss/sts、image/search、wiki/question、analysis/desc、wiki/remove、wiki/list、share/video）
    status: completed
  - id: oss
    content: 新建 Wiki/oss.ts，保留 ali-oss 上传逻辑；OSSKey 改为从 api.payload 读取
    status: completed
  - id: camera_picker
    content: 新建 Wiki/components/CameraPickerDialog.tsx（直接迁移原文件）
    status: completed
  - id: camera_view
    content: 新建 Wiki/views/CameraView.tsx，从 WikiCameraPage 移植；删掉 TokenDialog / onTokenChange / setUnauthorizedHandler；getUserMedia / navigate 改为父级回调；图片引用改 import
    status: completed
  - id: image_view
    content: 新建 Wiki/views/ImageView.tsx，从 WikiImagePage 移植；读 api 改 res.payload；跳转改为父级 goTo('detail', ...) 回调
    status: completed
  - id: detail_view
    content: 新建 Wiki/views/DetailView.tsx，从 WikiDetailPage 移植；读 api 改 res.payload；删除 react-router 用法
    status: completed
  - id: history_view
    content: 新建 Wiki/views/HistoryView.tsx，从 WikiHistoryPage 移植；跳转和返回改为回调
    status: completed
  - id: wiki_container
    content: 新建 Wiki/index.tsx：H5 守卫 + 视图状态机 + 内部栈实现返回上一视图
    status: completed
  - id: ai_job
    content: 在 src/pages/ai-job/index.tsx 添加 toolsType==='wiki' 分支，挂载 <Wiki />
    status: completed
  - id: ai_list_entry
    content: 在 src/pages/ai-list/index.tsx 的 localMap 添加 AI 百科入口（方便联调，可选）
    status: completed
  - id: verify_h5
    content: 本地 npm run dev:h5 验证：相机预览 / 识别 / 详情 / 历史 全链路
    status: completed
  - id: cleanup
    content: 删除 wiki-react/ 整个子目录
    status: completed
isProject: false
---

## 前置约束（必须周知）

- wiki-react 使用了 `navigator.mediaDevices.getUserMedia`、`ali-oss` 浏览器端 SDK、`SpeechSynthesis`、`<input type=file>`、`URL.createObjectURL` 等 **H5 专属 API**，在微信小程序 / 抖音 / 支付宝端无法运行。迁移后 `toolsType=wiki` 分支会在 Wiki 容器顶层做 `Taro.getEnv() !== ENV_TYPE.WEB` 守卫：非 H5 端渲染一段文案"该功能仅支持 H5 访问"，避免小程序构建或运行崩溃。
- `@tarojs/plugin-html` 已启用（[config/index.ts](config/index.ts)），H5 下 `<div>/<img>/<button>/<video>/<input>` 可直接使用，原代码 99% 无需改动。
- H5 开发代理已配置 `/api` → `https://api-test.maliang.miaobi.cn/`（[config/index.ts:143-151](config/index.ts)），与 wiki-react 原有代理规则完全一致。

## 路由与入口

- 在 [src/pages/ai-job/index.tsx](src/pages/ai-job/index.tsx) 增加一个分支：

```tsx
{
  router.params.toolsType === "wiki" ? <Wiki /> : null;
}
```

- 在 [src/pages/ai-list/index.tsx](src/pages/ai-list/index.tsx) 的 `localMap` 增加入口（方便联调）：
  `{ url: '/pages/ai-job/index?toolId=10&toolsType=wiki', title: 'AI 百科' }`
- 4 个子视图由 Wiki 组件通过内部 `useState` 状态机切换，传递 blob/File/wikiId 等数据；**不引入 react-router-dom**（KISS + YAGNI，单页面内部切换无需外部路由库）。

## 新增文件结构

```text
src/pages/ai-job/components/Wiki/
  index.tsx                 // 顶层容器 + H5 守卫 + 视图状态机
  views/
    CameraView.tsx          // 对应 WikiCameraPage
    ImageView.tsx           // 对应 WikiImagePage
    DetailView.tsx          // 对应 WikiDetailPage
    HistoryView.tsx         // 对应 WikiHistoryPage
  components/
    CameraPickerDialog.tsx  // 原 wiki-react 文件直接迁入，路径调整
  api.ts                    // 用 appRequest 改写原 api/wiki.ts
  oss.ts                    // 原 ali-oss 逻辑，基本不变
  types.ts                  // 原 types/index.ts
src/assets/images/wiki/
  ic_album_btn.webp、ic_back.webp、ic_capture_btn.webp、ic_history_btn.webp、
  ic_img_obj_bg.webp、ic_img_obj_tag_[lt|rt|lb|rb].webp、
  ic_wiki_bg_logo[1|2|3].webp、
  ic_wiki_detail_[delete|download|play]_btn.webp、ic_wiki_detail_title.webp、
  ic_wiki_img_obj_tag_btn.webp、ic_wiki_img_text_bar.webp、
  ic_wiki_img_text_right_arrow.webp、public_load_miaobi.gif
```

## 核心改动点

### 1. 视图状态机（取代 react-router）

在 `Wiki/index.tsx` 用一个 reducer/state 管理：

```ts
type WikiView =
  | { name: "camera" }
  | { name: "image"; imageUrl: string; file: File | Blob; wikiSubtype: string }
  | {
      name: "detail";
      wikiId: string;
      wikiSubtype: string;
      liveRoomId?: string;
      bgColor?: string;
    }
  | {
      name: "history";
      wikiSubtype: string;
      bgColor?: string;
      liveRoomId?: string;
    };
```

子视图通过 props 拿到 `goTo(view)` 与 `goBack()`，替换掉原 `useNavigate` / `useLocation`。History 的回退靠内部栈实现（`useRef<WikiView[]>`）。wikiSubtype 默认从 `router.params.subType` 读取（方便外部 URL 覆盖）。

### 2. API 层改造（`api.ts`）

沿用项目风格（[src/api/ai-story.ts](src/api/ai-story.ts)）：

```ts
import { isH5 } from "@/utils";
import appRequest from "@/utils/request";

const BASE_URL = isH5 ? "" : process.env.TARO_APP_API_TV_URL;

export const getWikiGuideVoice = () =>
  appRequest.get({ url: `${BASE_URL}/api/tv/box100/aiBK/get/voice` });

export const getWikiOssKey = () =>
  appRequest.get({ url: `${BASE_URL}/api/v1/oss/anon/sts` });

export const getObjectsFromPhoto = (url: string, type = "") =>
  appRequest.get({
    url: `${BASE_URL}/api/tv/box100/aiBK/image/search`,
    data: { url, type },
  });

export const getWikiByKeyword = (
  wikiId: string,
  type: string,
  liveRoomNo = 0,
) =>
  appRequest.get({
    url: `${BASE_URL}/api/tv/box100/aiBK/wiki/question`,
    data: { wikiId, type, liveRoomNo },
  });

export const getKeywordDesc = (keyword: string) =>
  appRequest.get({
    url: `${BASE_URL}/api/v4/wiki/anon/get/analysis/desc`,
    data: { keyword },
  });

export const removeWikiDetail = (wikiVoId: number) =>
  appRequest.get({
    url: `${BASE_URL}/api/tv/box100/aiBK/wiki/remove`,
    data: { wikiVoId },
  });

export const getWikiHistory = (type: string, page = 0, size = 100) =>
  appRequest.get({
    url: `${BASE_URL}/api/tv/box100/aiBK/wiki/list`,
    data: { page, size, type },
  });

export const getShareVideoInfo = (wikiVoId: number) =>
  appRequest.get({
    url: `${BASE_URL}/api/tv/box100/aiBK/share/video`,
    data: { id: wikiVoId },
  });
```

- 调用处把原 `await getXxx()` 返回对象读法从 `res` 改为 `res.payload`（对齐 `appRequest` 返回 `{code, payload, ...}`，见 [src/utils/request/request.ts:72](src/utils/request/request.ts)）。
- 401 处理由 `appRequest` 的拦截器统一接管，**删除 wiki-react 自带的 tokenStore、TokenDialog、setUnauthorizedHandler**（对应登录态已由 [src/app.tsx](src/app.tsx) 的 `autoLogin` 管理）。

### 3. OSS 上传（`oss.ts`）

- 原 [wiki-react/src/api/oss.ts](wiki-react/src/api/oss.ts) 几乎原样保留：`buildOssFileKey`、`uploadFileWithOssKey` 的 `ali-oss` 逻辑不变。
- `OSSKey` 从新 `api.ts` 的 `getWikiOssKey()` 返回 `payload` 中取（`res.payload as OSSKey`）。

### 4. 资源引用

把所有 `src="/assets/xxx.webp"` 改为 `import` 形式，与现有页面一致（参见 [src/pages/ai-job-detail/components/AiStory/index.tsx](src/pages/ai-job-detail/components/AiStory/index.tsx)）：

```ts
import bgLogo1 from "@/assets/images/wiki/ic_wiki_bg_logo1.webp";
// ... <img src={bgLogo1} />
```

这样能走 Taro 的 `imageUrlLoaderOption`，生产环境自动走 CDN。

### 5. H5 守卫

在 `Wiki/index.tsx` 顶层：

```tsx
import Taro from "@tarojs/taro";
if (Taro.getEnv() !== Taro.ENV_TYPE.WEB) {
  return <div className="p-[40px] text-center">该功能仅支持 H5 访问</div>;
}
```

此外对 `navigator.mediaDevices`、`window.speechSynthesis` 的直接引用再加 `typeof window !== 'undefined'` 防御（保险起见，防小程序构建阶段静态求值报错）。

### 6. 依赖变更（`package.json`）

- 新增 `ali-oss`（运行时）、`@types/ali-oss`（dev）。
- **不新增** `react-router-dom`（用不上）。
- 不触碰 `react` / `@tarojs/*` 版本。

### 7. 清理

- 删除整个 `wiki-react/` 目录（用户确认）。

## 验收点（提交前自查）

- `toolsType=wiki` 在 H5 下可完成「相机 → 识别 → 详情 → 历史」完整闭环。
- `toolsType !== wiki` 的现有 3 个分支（txt2img / pic2dance / ai_story）行为无变化。
- 微信小程序构建（`npm run build:test`）不报错（依赖 ali-oss 只在 Wiki 分支运行时引入；`import OSS from 'ali-oss'` 放在 `oss.ts` 里，小程序 tree-shake 不到 Wiki 组件就不会用到；若 Taro 静态分析仍打包 ali-oss 导致体积/兼容问题，则用 `import('ali-oss')` 动态 import 兜底）。
- H5 编译（`npm run build:h5:test`）通过，无 TS 错误。
