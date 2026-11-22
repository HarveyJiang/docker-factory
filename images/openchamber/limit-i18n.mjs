import { readFileSync, writeFileSync } from 'node:fs';

// 只保留 en（类型与回退基准）和 zh-CN 两套界面语言。
// 上游 store.ts 用 15 个动态 import 分别打包每种语言，vite 会为每种语言把 ~130 个
// i18n 片段各切一遍（900KB 的 integrations-catalog 还会让 Babel 反复打印 deoptimise
// 告警），构建时间与 dist 体积都随语言数线性放大。
// 这里把动态 import 收敛到 zh-CN，LOCALES 只留 en/zh-CN（设置里的语言选择器随之只剩
// 两项），其它语言回落到 en，繁中回落到简中。
// 由 images/openchamber/Dockerfile 在 builder 阶段调用：bun /tmp/limit-i18n.mjs
const dir = process.argv[2] ?? '/app/packages/ui/src/lib/i18n';

const storePath = `${dir}/store.ts`;
const store = readFileSync(storePath, 'utf8');
const start = store.indexOf('async function loadDictionary');
const end = store.indexOf('export const useI18nStore', start);
if (start < 0 || end < 0) {
  throw new Error('store.ts: 找不到 loadDictionary / useI18nStore，上游结构可能已变更');
}
const loadDictionary = `async function loadDictionary(locale: Locale): Promise<I18nDictionary> {
  const cached = dictionaries.get(locale);
  if (cached) {
    return cached;
  }

  const dictionary = locale === 'zh-CN'
    ? (await import('./messages/zh-CN') as { dict: I18nDictionary }).dict
    : enDict;
  dictionaries.set(locale, dictionary);
  return dictionary;
}

`;
writeFileSync(storePath, store.slice(0, start) + loadDictionary + store.slice(end));

const runtimePath = `${dir}/runtime.ts`;
const runtime = readFileSync(runtimePath, 'utf8');
const withLocales = runtime.replace(
  /^export const LOCALES = \[[^\]]*\] as const satisfies readonly Locale\[\];$/m,
  "export const LOCALES = ['en', 'zh-CN'] as const satisfies readonly Locale[];",
);
if (withLocales === runtime) {
  throw new Error('runtime.ts: 找不到 LOCALES 定义，上游结构可能已变更');
}

// 语言选择器只剩 en/zh-CN 之后，浏览器语言或已存偏好里的其它语言要能落回这两项：
// 繁中落到简中，其余落到 en。
const normalizeFrom = `export function normalizeLocale(value: string | undefined | null): Locale {
  return supportedLocale(value) ?? DEFAULT_LOCALE;
}`;
const normalizeTo = `export function normalizeLocale(value: string | undefined | null): Locale {
  const locale = supportedLocale(value);
  return locale === 'zh-CN' || locale === 'zh-TW' ? 'zh-CN' : DEFAULT_LOCALE;
}`;
const withNormalize = withLocales.replace(normalizeFrom, normalizeTo);
if (withNormalize === withLocales) {
  throw new Error('runtime.ts: 找不到 normalizeLocale，上游结构可能已变更');
}
writeFileSync(runtimePath, withNormalize);

console.log('[i18n] 已限制为 en + zh-CN（其它语言回落到 en，繁中回落到简中）');
