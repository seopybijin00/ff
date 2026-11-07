/* 자기 관리 연습실 – Supabase 연결 층
 * config.js 의 두 칸(SUPABASE_URL, SUPABASE_ANON_KEY)이 채워져 있고 vendor/supabase.js 가 불러와졌을 때만 켜진다(CLOUD.on).
 * 꺼져 있으면 앱은 예전처럼 이 기기(localStorage)에만 저장한다.
 * 이 파일은 서버 통신만 맡고, 화면은 건드리지 않는다. 모든 서버 호출은 실패해도 앱이 멈추지 않게 예외를 밖으로 넘긴다. */
(function () {
  const cfg = window.NAILCARE_CONFIG || {};
  const lib = window.supabase;
  const C = (window.CLOUD = { on: false, photos: [] });
  if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY || !lib || !lib.createClient) return;

  const sb = lib.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    // 선생님 로그인은 이 탭 메모리에만 둔다: 새로고침하거나 탭을 닫으면 로그아웃(공용 태블릿 보호)
    auth: { persistSession: false, autoRefreshToken: true, detectSessionInUrl: false },
    realtime: { params: { eventsPerSecond: 5 } }
  });
  C.on = true;
  C.sb = sb;

  const ok = (r) => { if (r.error) throw r.error; return r.data; };

  // ── 학생 쪽(로그인 없이 이름 카드 + 숫자 4자리) ──
  C.roster = async () => ok(await sb.rpc('get_roster'));
  C.login = async (id, pin) => ok(await sb.rpc('student_login', { p_id: id, p_pin: pin }));

  // 진도 저장: 2초 모아서 한 번만 보내고, 화면을 닫을 때 마지막으로 한 번 더 보낸다
  let saveT = null, pending = null;
  const flush = async () => {
    clearTimeout(saveT); saveT = null;
    const m = pending; pending = null;
    if (!m) return;
    try {
      ok(await sb.rpc('student_save', { p_id: m.id, p_pin: m.pin, p_unl: m.unl, p_prog: m.prog, p_auto: m.auto }));
    } catch (e) { pending = pending || m; C.lastError = e; }
  };
  C.save = (me) => {
    if (!me || !me.id || !me._pin) return;
    pending = { id: me.id, pin: me._pin, unl: me.unl || {}, prog: me.prog || {}, auto: me.autoRead == null ? null : !!me.autoRead };
    clearTimeout(saveT); saveT = setTimeout(flush, 2000);
  };
  C.flush = flush;
  addEventListener('pagehide', flush);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') flush(); });

  C.help = async (me, at) => ok(await sb.rpc('student_help', { p_id: me.id, p_pin: me._pin, p_at: at }));
  C.photo = async (me, photoId, img) => ok(await sb.rpc('student_add_photo', { p_id: me.id, p_pin: me._pin, p_photo_id: photoId, p_img: img }));

  // ── 선생님 쪽(이메일 + 비밀번호로 로그인, 선생님으로 등록된 계정만 통과) ──
  C.tIn = async (email, password) => {
    const r = await sb.auth.signInWithPassword({ email, password });
    if (r.error) return { ok: false, bad: true };
    const t = await sb.rpc('is_teacher');
    if (t.error || t.data !== true) { await sb.auth.signOut(); return { ok: false, notTeacher: true }; }
    return { ok: true };
  };

  const toStu = (s) => ({
    id: s.id, name: s.name, av: s.avatar, unl: s.unl || {}, prog: s.prog || {},
    autoRead: s.auto_read, last: s.last_at ? Date.parse(s.last_at) : 0, help: s.help || undefined
  });
  C.toStu = toStu;

  C.tLoad = async () => {
    const [st, ph, se] = await Promise.all([
      sb.from('students').select('id,name,avatar,unl,prog,auto_read,last_at,help').order('created_at'),
      sb.from('cert_photos').select('id,student_id,taken_at,img').order('taken_at', { ascending: false }).limit(60),
      sb.from('settings').select('def_auto').eq('id', 1).maybeSingle()
    ]);
    const students = ok(st).map(toStu);
    const byId = {}; students.forEach((s) => (byId[s.id] = s));
    C.photos = ok(ph).map((p) => ({
      id: p.id, t: Date.parse(p.taken_at), img: p.img,
      name: (byId[p.student_id] || {}).name || '?', av: (byId[p.student_id] || {}).av || ''
    }));
    return { students, defAuto: !!(ok(se) || {}).def_auto };
  };

  C.tUpdate = async (id, fields) => ok(await sb.from('students').update(fields).eq('id', id));
  C.tDelete = async (id) => ok(await sb.from('students').delete().eq('id', id));
  C.tAdd = async (name, pin, avatar) => ok(await sb.rpc('teacher_add_student', { p_name: name, p_pin: pin, p_avatar: avatar }));
  C.tSetPin = async (id, pin) => ok(await sb.rpc('teacher_set_student_pin', { p_id: id, p_pin: pin }));
  C.tDefAuto = async (v) => ok(await sb.from('settings').update({ def_auto: !!v }).eq('id', 1));
  C.tDelPhoto = async (id) => ok(await sb.from('cert_photos').delete().eq('id', id));

  // 학생이 도움을 누르거나 사진을 찍으면 선생님 화면이 바로 바뀐다(Realtime)
  let ch = null, tm = null;
  C.tWatch = (cb) => {
    if (ch) return; // 이미 보고 있으면 다시 만들지 않는다
    const fire = () => { clearTimeout(tm); tm = setTimeout(cb, 400); };
    ch = sb.channel('teacher-live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'students' }, fire)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'cert_photos' }, fire)
      .subscribe();
  };
  C.tUnwatch = () => { clearTimeout(tm); if (ch) { sb.removeChannel(ch); ch = null; } };
  C.tOut = async () => { C.tUnwatch(); C.photos = []; try { await sb.auth.signOut(); } catch (e) {} };
})();
