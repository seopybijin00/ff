// Supabase 연결 정보. anon(공개) 키는 공개되어도 되는 값이고, 실제 보안은 supabase/schema.sql 의 규칙이 지킵니다.
// (service_role 키는 절대 넣지 마세요.) 두 칸을 비우면 "이 기기에만 저장" 모드로 돌아갑니다.
// Vercel 환경 변수 SUPABASE_URL / SUPABASE_ANON_KEY 를 설정하면 배포 때 이 파일이 그 값으로 덮어써집니다.
window.NAILCARE_CONFIG = {
  SUPABASE_URL: "https://earwwqbsduuimibmoklf.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVhcnd3cWJzZHV1aW1pYm1va2xmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM4NzY3MTIsImV4cCI6MjEwOTQ1MjcxMn0.My16VBGwvFx2VKf1etQFVlBnqVepWa51UPwU4ti_cqs"
};
