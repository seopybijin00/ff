# 자기 관리 연습실: 손톱 관리

특수학급 학생들이 웹캠·태블릿으로 손톱 관리를 연습하는 웹앱입니다.
**GitHub**(코드 보관) → **Vercel**(웹 주소로 배포) → **Supabase**(학생 진도·도움 요청·인증 사진 저장)로 연결됩니다.

```
public/index.html      앱 본체(기존 코드 그대로 + 클라우드 연결 부분만 추가)
public/cloud.js        Supabase 통신 담당(설정이 비어 있으면 꺼짐)
public/config.js       Supabase 주소·공개 키를 넣는 곳
public/vendor/         supabase-js (브라우저용, 직접 포함)
supabase/schema.sql    표·보안 규칙·함수(한 번만 실행)
scripts/make-config.js Vercel 빌드 때 환경 변수로 config.js 를 만들어 줌
vercel.json            배포 설정(카메라 허용 헤더 포함)
```

설정 두 칸(`SUPABASE_URL`, `SUPABASE_ANON_KEY`)이 **비어 있으면 예전처럼 "이 기기에만 저장"** 모드로 그대로 동작합니다. 그래서 Supabase를 연결하기 전에도 배포해서 확인할 수 있어요.

## 1. Supabase 만들기 (약 10분)
1. https://supabase.com 에서 새 프로젝트를 만듭니다(지역은 Seoul 추천).
2. 왼쪽 **SQL Editor → New query** 에 `supabase/schema.sql` 내용을 붙여 넣고 **Run**. (여러 번 실행해도 안전합니다.)
3. **Authentication → Users → Add user** 로 선생님 계정을 만듭니다(이메일 + 비밀번호, *Auto Confirm User* 체크).
4. **Authentication → Sign In / Providers**(또는 Settings)에서 **Allow new users to sign up 을 끕니다.** (아무나 계정을 만들지 못하게)
5. SQL Editor 에서 선생님 등록(이메일을 바꿔서 실행):
   ```sql
   insert into public.teachers (user_id) select id from auth.users where email = '선생님@이메일';
   ```
6. **Project Settings → API** 에서 **Project URL** 과 **anon(public) key**(새 화면에서는 *publishable key*)를 복사해 둡니다.
   - ⚠️ `service_role` / *secret* 키는 절대 넣지 마세요.

> Realtime(도움 요청이 선생님 화면에 바로 뜨는 기능)은 `schema.sql` 이 켜 둡니다.

## 2. GitHub 에 올리기
```bash
cd nailcare-repo
git init && git add . && git commit -m "손톱 관리 연습실"
git branch -M main
git remote add origin https://github.com/내아이디/nailcare.git
git push -u origin main
```
(저장소는 **Private** 을 권장합니다.)

## 3. Vercel 로 배포
1. https://vercel.com → **Add New → Project** → 방금 만든 GitHub 저장소를 **Import**.
2. Framework Preset: **Other**. 나머지는 `vercel.json` 이 알아서 합니다(Build: `node scripts/make-config.js`, Output: `public`).
3. **Environment Variables** 에 두 개를 추가합니다.
   - `SUPABASE_URL` = Project URL (예: `https://abcd1234.supabase.co`)
   - `SUPABASE_ANON_KEY` = anon(publishable) key
4. **Deploy**. 이후 `git push` 만 하면 자동으로 다시 배포됩니다.
5. 나온 주소(https://…vercel.app)를 QR 코드로 만들어 태블릿에서 엽니다. (카메라는 https 에서만 동작합니다.)

## 4. 확인하기
- 선생님 화면: 로그인 화면 → **👩‍🏫 선생님** → 이메일·비밀번호 → 학생 추가(이름 + 숫자 4자리).
- 다른 태블릿에서 학생 카드 → 비밀번호 → 활동. 진도는 몇 초 안에 서버에 저장됩니다.
- 학생이 **선생님 도와주세요**를 누르면 선생님 화면에 🙋 도움이 바로 뜹니다.
- 선생님은 **✅ 끝내기**를 누르면 로그아웃됩니다(새로고침해도 로그아웃).

## 안전·개인정보 메모
- **anon 키는 공개되어도 되는 값**입니다. 실제 보호는 `schema.sql` 의 규칙이 합니다: 학생 표는 선생님만 읽고 쓸 수 있고, 학생은 정해진 함수로 *자기 비밀번호가 맞을 때만* 자기 기록을 읽고 저장합니다. 비밀번호는 서버에서 bcrypt 로 암호화해 저장하고, 5번 틀리면 1분간 잠깁니다.
- 학생 이름·진도·**얼굴이 나올 수 있는 인증 사진**이 서버(Supabase)에 저장됩니다. 학생 **별명** 사용, 사진 사용 **보호자 동의**, 학기 말 삭제(선생님 화면 🗑)를 권장합니다. 학생을 지우면 그 학생의 사진도 함께 지워집니다.
- 선생님 로그인은 탭 메모리에만 유지됩니다(공용 태블릿 보호).
- 인터넷이 끊기면 학생 목록을 불러오지 못하고 *손님으로 하기*만 가능합니다(손님은 원래도 저장하지 않습니다).
- Supabase 무료 플랜은 7일 동안 접속이 없으면 프로젝트가 일시 중지됩니다. 방학 뒤에는 대시보드에서 **Restore** 를 눌러 주세요.

## 내 컴퓨터에서 확인하기
```bash
cd public && python3 -m http.server 8080   # http://localhost:8080 (localhost 는 카메라 허용)
```
