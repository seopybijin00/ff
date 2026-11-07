// Vercel 빌드 때 실행: 환경 변수로 public/config.js 를 만든다. 환경 변수가 없으면 건드리지 않는다.
const fs = require('fs'), path = require('path');
const url = (process.env.SUPABASE_URL || '').trim();
const key = (process.env.SUPABASE_ANON_KEY || '').trim();
if (!url || !key) { console.log('[make-config] SUPABASE_URL / SUPABASE_ANON_KEY 가 없어 public/config.js 를 그대로 둡니다.'); process.exit(0); }
if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url)) { console.error('[make-config] SUPABASE_URL 모양이 이상해요: https://프로젝트ID.supabase.co'); process.exit(1); }
if (/service_role/i.test(key) || key.split('.').length === 3 && JSON.parse(Buffer.from(key.split('.')[1], 'base64').toString()).role === 'service_role') {
  console.error('[make-config] service_role 키는 절대 넣으면 안 돼요. anon(공개) 키를 넣어 주세요.'); process.exit(1);
}
const body = '// 자동 생성(scripts/make-config.js)\nwindow.NAILCARE_CONFIG = ' + JSON.stringify({ SUPABASE_URL: url.replace(/\/$/, ''), SUPABASE_ANON_KEY: key }, null, 2) + ';\n';
fs.writeFileSync(path.join(__dirname, '..', 'public', 'config.js'), body);
console.log('[make-config] public/config.js 를 만들었어요.');
