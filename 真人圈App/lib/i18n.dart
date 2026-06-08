// 多语言:中文 / English / العربية(阿拉伯语自动 RTL)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class L10n extends ChangeNotifier {
  static final L10n instance = L10n._();
  L10n._();

  String lang = 'zh';
  bool get isRtl => lang == 'ar';
  Locale get locale => Locale(lang);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    lang = sp.getString('lang') ?? 'zh';
    notifyListeners();
  }

  Future<void> set(String l) async {
    lang = l;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('lang', l);
    notifyListeners();
  }

  String t(String k) => (_S[lang]?[k]) ?? (_S['zh']?[k]) ?? k;

  static const Map<String, Map<String, String>> _S = {
    'zh': {
      'app': '真人圈', 'sub': '没有 AI 美女,没有机器人。只有真人。',
      'login': '登录', 'register': '注册', 'phone': '手机号', 'pwd': '密码(至少6位)', 'nick': '昵称',
      'toReg': '注册(下一步:活体验证)', 'have': '已有账号,登录',
      'agree': '注册即同意:① 账号须通过活体验证 ② AI 生成内容零容忍 ③ 一人一号,人脸特征哈希去重(不存原图)',
      'feed': '真人圈', 'video': '视频', 'events': '线下局', 'chat': '消息', 'me': '我的',
      'noai': '全站 0 条 AI 内容', 'publish': '发布', 'all': '推荐', 'following': '关注',
      'placeholder': '此刻,真实地记录…(AI 生成内容将被检测并封号)',
      'direct': 'App 直拍(签名认证)', 'reportAI': '疑似AI?', 'comment': '评论', 'send': '发送',
      'liveTitle': '3D 活体人脸检测', 'liveDesc': '确认你是真人并防止重复注册。原始图像验证后立即删除,仅保留不可逆特征哈希。(本测试为模拟流程)',
      'liveStart': '开始活体检测', 'liveLater': '稍后(仅可浏览)', 'congrats': '恭喜!你现在是 L2 认证真人',
      'follow': '关注', 'unfollow': '已关注', 'dm': '私信', 'edit': '编辑资料', 'logout': '退出登录',
      'followers': '粉丝', 'followingC': '关注', 'meet': '线下见面',
      'join': '报名', 'joined': '已报名 ✓', 'full': '已满员', 'newEvent': '发起活动',
      'noConv': '暂无会话', 'hello': '打个招呼吧 👋', 'sayhi': '说点什么…(端到端加密)',
      'notif': '通知', 'noNotif': '暂无通知', 'search': '搜索真人 / 内容',
      'aiblocked': '检测到 AI 生成内容,已拒绝发布', 'empty': '还没有内容', 'save': '保存',
      'encrypted': '🔒 端到端加密 · 全真人', 'bioEmpty': '这个真人很懒,什么都没写',
    },
    'en': {
      'app': 'RealCircle', 'sub': 'No AI girls. No bots. Only real humans.',
      'login': 'Log in', 'register': 'Sign up', 'phone': 'Phone', 'pwd': 'Password (min 6)', 'nick': 'Nickname',
      'toReg': 'Sign up (next: liveness)', 'have': 'Have an account? Log in',
      'agree': 'By signing up: ① must pass liveness ② zero tolerance for AI ③ one person one account, face-hash dedup (no raw image)',
      'feed': 'Feed', 'video': 'Video', 'events': 'Meetups', 'chat': 'Chats', 'me': 'Me',
      'noai': '0 AI content', 'publish': 'Post', 'all': 'For you', 'following': 'Following',
      'placeholder': 'Capture this moment, for real… (AI content is banned)',
      'direct': 'In-app capture (signed)', 'reportAI': 'Looks AI?', 'comment': 'Comment', 'send': 'Send',
      'liveTitle': '3D Liveness Check', 'liveDesc': 'Confirms you are a real, unique person. Raw image deleted right after; only a hash kept. (Simulated here)',
      'liveStart': 'Start liveness', 'liveLater': 'Later (browse only)', 'congrats': 'You are now an L2 verified human!',
      'follow': 'Follow', 'unfollow': 'Following', 'dm': 'Message', 'edit': 'Edit profile', 'logout': 'Log out',
      'followers': 'Followers', 'followingC': 'Following', 'meet': 'Met IRL',
      'join': 'Join', 'joined': 'Joined ✓', 'full': 'Full', 'newEvent': 'New meetup',
      'noConv': 'No chats yet', 'hello': 'Say hi 👋', 'sayhi': 'Say something… (E2E encrypted)',
      'notif': 'Notifications', 'noNotif': 'No notifications', 'search': 'Search people / posts',
      'aiblocked': 'AI content detected, post rejected', 'empty': 'Nothing here yet', 'save': 'Save',
      'encrypted': '🔒 E2E encrypted · all real', 'bioEmpty': 'No bio yet',
    },
    'ar': {
      'app': 'الدائرة الحقيقية', 'sub': 'لا فتيات ذكاء اصطناعي. لا روبوتات. بشر حقيقيون فقط.',
      'login': 'تسجيل الدخول', 'register': 'إنشاء حساب', 'phone': 'الجوال', 'pwd': 'كلمة المرور (6+)', 'nick': 'الاسم',
      'toReg': 'إنشاء حساب (التالي: الحيوية)', 'have': 'لديك حساب؟ سجّل الدخول',
      'agree': 'بالتسجيل: ① اجتياز الحيوية ② صفر تسامح مع الذكاء الاصطناعي ③ شخص واحد لحساب واحد، تجزئة الوجه دون حفظ الصورة',
      'feed': 'الرئيسية', 'video': 'فيديو', 'events': 'لقاءات', 'chat': 'الرسائل', 'me': 'حسابي',
      'noai': 'صفر محتوى ذكاء اصطناعي', 'publish': 'نشر', 'all': 'مقترح', 'following': 'أتابع',
      'placeholder': 'وثّق هذه اللحظة بصدق… (يُحظر محتوى الذكاء الاصطناعي)',
      'direct': 'تصوير داخل التطبيق (موقّع)', 'reportAI': 'يبدو مزيّفاً؟', 'comment': 'تعليق', 'send': 'إرسال',
      'liveTitle': 'فحص الوجه الحي', 'liveDesc': 'يؤكد أنك شخص حقيقي وفريد. تُحذف الصورة فوراً ويُحفظ تجزئة فقط. (محاكاة)',
      'liveStart': 'ابدأ الفحص', 'liveLater': 'لاحقاً (تصفّح فقط)', 'congrats': 'أنت الآن إنسان موثّق L2!',
      'follow': 'متابعة', 'unfollow': 'أتابع', 'dm': 'رسالة', 'edit': 'تعديل الملف', 'logout': 'تسجيل الخروج',
      'followers': 'متابِعون', 'followingC': 'أتابع', 'meet': 'لقاءات واقعية',
      'join': 'انضمام', 'joined': 'مشترك ✓', 'full': 'مكتمل', 'newEvent': 'لقاء جديد',
      'noConv': 'لا محادثات', 'hello': 'ألقِ التحية 👋', 'sayhi': 'اكتب شيئاً… (مشفّر)',
      'notif': 'الإشعارات', 'noNotif': 'لا إشعارات', 'search': 'ابحث عن أشخاص / منشورات',
      'aiblocked': 'تم اكتشاف محتوى ذكاء اصطناعي، رُفض', 'empty': 'لا شيء بعد', 'save': 'حفظ',
      'encrypted': '🔒 مشفّر · بشر فقط', 'bioEmpty': 'لا نبذة بعد',
    },
  };
}
