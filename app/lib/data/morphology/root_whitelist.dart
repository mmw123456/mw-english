import '../models/word_detail.dart';

/// 前后缀分析的**精确白名单**。
///
/// 规则：只有在这个表里的词才显示拆解，没命中整个区块不显示。
/// 不做「前缀可剥就剥、词根能模糊匹配就配」的规则拆解 —— 那样会拆出
/// `instruct → in(向)`、`reluctant → re + luc(光)` 这类错（见项目日志踩坑 23）。
///
/// 收录标准：拉丁/希腊词源的词，拆出来的每个成分在词源上真实存在，
/// 且拼写没有发生无法解释的音变。缩写词、拟声词、来源不明的一律不收。
/// `note` 写清「为什么这么拆」，用户看到拆解时能自己判断对不对。
final Map<String, RootAnalysis> kRootWhitelist = <String, RootAnalysis>{
  // ===== A =====
  'abrupt': RootAnalysis(
    parts: [Morpheme.p('ab', '离开'), Morpheme.r('rupt', '断裂（rumpere）')],
    note: 'ab-「离开」+ rumpere「断裂」→ 突然断掉的：唐突的',
  ),
  'absolve': RootAnalysis(
    parts: [Morpheme.p('ab', '离开'), Morpheme.r('solv', '松开（solvere）')],
    note: 'ab- + solvere「松开」→ 把人从罪责里松开：赦免',
  ),
  'absorb': RootAnalysis(
    parts: [Morpheme.p('ab', '离开、 away'), Morpheme.r('sorb', '吸（sorbere）')],
    note: 'ab- + sorbere「吸」→ 吸走：吸收',
  ),
  'abstract': RootAnalysis(
    parts: [
      Morpheme.p('abs', '离开'),
      Morpheme.r('tract', '拉（trahere）'),
    ],
    note: 'abs-「离开」+ trahere「拉」→ 从具体事物里抽离出来的：抽象的',
  ),
  'abundant': RootAnalysis(
    parts: [
      Morpheme.p('ab', '加强语气'),
      Morpheme.r('und', '波浪、涌出（unda）'),
      Morpheme.s('ant', '形容词后缀'),
    ],
    note: 'ab- + unda「波浪」→ 像水一样漫出来的：丰富的',
  ),
  'access': RootAnalysis(
    parts: [Morpheme.p('ac', '向（ad-）'), Morpheme.r('cess', '走（cedere）')],
    note: 'ad- + cedere「走」→ 走到跟前：接近、进入',
  ),
  'accord': RootAnalysis(
    parts: [Morpheme.p('ac', '向（ad-）'), Morpheme.r('cord', '心（cor）')],
    note: 'ad- + cor「心」→ 心往一处靠：一致、符合',
  ),
  'accumulate': RootAnalysis(
    parts: [
      Morpheme.p('ac', '向（ad-）'),
      Morpheme.r('cumul', '堆（cumulus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ad- + cumulus「堆」→ 往一起堆：积累',
  ),
  'accuse': RootAnalysis(
    parts: [Morpheme.p('ac', '向（ad-）'), Morpheme.r('cus', '原因、诉讼（causa）')],
    note: 'ad- + causa「诉讼」→ 把官司指向某人：控告',
  ),
  'adequate': RootAnalysis(
    parts: [
      Morpheme.p('ad', '向'),
      Morpheme.r('equ', '相等（aequus）'),
      Morpheme.s('ate', '形容词后缀'),
    ],
    note: 'ad- + aequus「相等」→ 拉平到够用的程度：足够的',
  ),
  'adolescent': RootAnalysis(
    parts: [
      Morpheme.p('ad', '向'),
      Morpheme.r('olesc', '生长（alescere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'ad- + alescere「开始生长」→ 正在长起来的：青春期的',
  ),
  'advent': RootAnalysis(
    parts: [Morpheme.p('ad', '向'), Morpheme.r('vent', '来（venire）')],
    note: 'ad- + venire「来」→ 到来',
  ),
  'advocate': RootAnalysis(
    parts: [
      Morpheme.p('ad', '向'),
      Morpheme.r('voc', '叫、喊（vocare）'),
      Morpheme.s('ate', '名词/动词后缀'),
    ],
    note: 'ad- + vocare「喊」→ 朝着某方发声：提倡、拥护者',
  ),
  'aeroplane': RootAnalysis(
    parts: [Morpheme.r('aero', '空气（希腊 aēr）'), Morpheme.r('plane', '平面、滑翔')],
    note: 'aero-「空气」+ plane「平面」→ 在空中滑行的：飞机',
  ),
  'aesthetic': RootAnalysis(
    parts: [Morpheme.r('aesthet', '感知（希腊 aisthēsis）'), Morpheme.s('ic', '形容词后缀')],
    note: '希腊 aisthēsis「感知」→ 与感官感受有关的：审美的',
  ),
  'affirmation': RootAnalysis(
    parts: [
      Morpheme.p('af', '向（ad-）'),
      Morpheme.r('firm', '坚固（firmus）'),
      Morpheme.s('ation', '名词后缀'),
    ],
    note: 'ad- + firmus「坚固」→ 把话说定：肯定、断言',
  ),
  'affluent': RootAnalysis(
    parts: [
      Morpheme.p('af', '向（ad-）'),
      Morpheme.r('flu', '流（fluere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'ad- + fluere「流」→ 财富往这边流：富裕的',
  ),
  'aggravate': RootAnalysis(
    parts: [
      Morpheme.p('ag', '向（ad-）'),
      Morpheme.r('grav', '重（gravis）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ad- + gravis「重」→ 往上加重量：加重、恶化',
  ),
  'allergy': RootAnalysis(
    parts: [
      Morpheme.r('all', '其他（希腊 allos）'),
      Morpheme.r('erg', '作用（希腊 ergon）'),
      Morpheme.s('y', '名词后缀'),
    ],
    note: 'allos「其他」+ ergon「作用」→ 对异物产生异常反应：过敏',
  ),
  'alleviate': RootAnalysis(
    parts: [
      Morpheme.p('al', '向（ad-）'),
      Morpheme.r('levi', '轻（levis）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ad- + levis「轻」→ 把负担变轻：缓解',
  ),
  'alliance': RootAnalysis(
    parts: [
      Morpheme.p('al', '向（ad-）'),
      Morpheme.r('li', '捆绑（ligare）'),
      Morpheme.s('ance', '名词后缀'),
    ],
    note: 'ad- + ligare「捆绑」→ 绑在一起：联盟',
  ),
  'allocate': RootAnalysis(
    parts: [
      Morpheme.p('al', '向（ad-）'),
      Morpheme.r('loc', '地方（locus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ad- + locus「地方」→ 把东西分到各处的位子上：分配',
  ),
  'allure': RootAnalysis(
    parts: [Morpheme.p('al', '向（ad-）'), Morpheme.r('lure', '诱饵')],
    note: 'ad- + lure「诱饵」→ 用饵把人引过来：诱惑',
  ),
  'ally': RootAnalysis(
    parts: [Morpheme.p('al', '向（ad-）'), Morpheme.r('ly', '捆绑（ligare）')],
    note: 'ad- + ligare「捆绑」→ 绑到同一阵营：结盟、盟友',
  ),
  'alternate': RootAnalysis(
    parts: [Morpheme.r('altern', '交替（alter「另一个」）'), Morpheme.s('ate', '后缀')],
    note: 'alter「另一个」→ 一个接一个轮换：交替的',
  ),
  'altitude': RootAnalysis(
    parts: [Morpheme.r('alt', '高（altus）'), Morpheme.s('itude', '名词后缀')],
    note: 'altus「高」+ -itude → 高度、海拔',
  ),
  'amplify': RootAnalysis(
    parts: [Morpheme.r('ampl', '大（amplus）'), Morpheme.s('ify', '使…化')],
    note: 'amplus「大」+ -ify「使」→ 使变大：放大',
  ),
  'antique': RootAnalysis(
    parts: [Morpheme.r('ant', '在前（ante）'), Morpheme.s('ique', '形容词后缀')],
    note: 'ante「在前」→ 属于从前的东西：古董的',
  ),
  'antibiotic': RootAnalysis(
    parts: [
      Morpheme.p('anti', '抗、反'),
      Morpheme.r('bio', '生命（希腊 bios）'),
      Morpheme.s('tic', '形容词后缀'),
    ],
    note: 'anti-「抗」+ bios「生命」→ 对抗微生物的：抗生素',
  ),
  'appetite': RootAnalysis(
    parts: [
      Morpheme.p('ap', '向（ad-）'),
      Morpheme.r('pet', '追求（petere）'),
      Morpheme.s('ite', '名词后缀'),
    ],
    note: 'ad- + petere「追求」→ 朝食物扑上去的欲望：食欲',
  ),
  'appliance': RootAnalysis(
    parts: [
      Morpheme.p('ap', '向（ad-）'),
      Morpheme.r('pli', '折、贴合（plicare）'),
      Morpheme.s('ance', '名词后缀'),
    ],
    note: 'ad- + plicare「贴合」→ 把工具用在某处：器具',
  ),
  'appraisal': RootAnalysis(
    parts: [
      Morpheme.p('ap', '向（ad-）'),
      Morpheme.r('prais', '价格（pretium）'),
      Morpheme.s('al', '名词后缀'),
    ],
    note: 'ad- + pretium「价格」→ 给个价：评估',
  ),
  'appropriate': RootAnalysis(
    parts: [
      Morpheme.p('ap', '向（ad-）'),
      Morpheme.r('propri', '自己的（proprius）'),
      Morpheme.s('ate', '形容词后缀'),
    ],
    note: 'ad- + proprius「自己的」→ 正好归它所有：恰当的',
  ),
  'approximate': RootAnalysis(
    parts: [
      Morpheme.p('ap', '向（ad-）'),
      Morpheme.r('proxim', '最近（proximus）'),
      Morpheme.s('ate', '后缀'),
    ],
    note: 'ad- + proximus「最近的」→ 贴近真值：近似的',
  ),
  'arithmetic': RootAnalysis(
    parts: [Morpheme.r('arithm', '数（希腊 arithmos）'), Morpheme.s('etic', '学科后缀')],
    note: '希腊 arithmos「数」→ 算术',
  ),
  'armpit': RootAnalysis(
    parts: [Morpheme.r('arm', '手臂'), Morpheme.r('pit', '凹坑')],
    note: 'arm「臂」+ pit「坑」→ 腋窝',
  ),
  'array': RootAnalysis(
    parts: [Morpheme.p('ar', '向（ad-）'), Morpheme.r('ray', '排列、准备')],
    note: '古法语 arei「布置」→ 排开的一列：阵列',
  ),
  'ascend': RootAnalysis(
    parts: [Morpheme.p('a', '向上（ad-）'), Morpheme.r('scend', '爬（scandere）')],
    note: 'ad- + scandere「爬」→ 往上爬：上升',
  ),
  'ascribe': RootAnalysis(
    parts: [Morpheme.p('a', '向（ad-）'), Morpheme.r('scrib', '写（scribere）')],
    note: 'ad- + scribere「写」→ 把原因写到某人账上：归因于',
  ),
  'aspect': RootAnalysis(
    parts: [Morpheme.p('a', '向（ad-）'), Morpheme.r('spect', '看（specere）')],
    note: 'ad- + specere「看」→ 看向的那一面：方面',
  ),
  'assemble': RootAnalysis(
    parts: [Morpheme.p('as', '向（ad-）'), Morpheme.r('sembl', '一起（similis）')],
    note: 'ad- + similis「相似、一起」→ 聚到一起：集合、组装',
  ),
  'assembly': RootAnalysis(
    parts: [
      Morpheme.p('as', '向（ad-）'),
      Morpheme.r('sembl', '一起（similis）'),
      Morpheme.s('y', '名词后缀'),
    ],
    note: '同 assemble：聚起来的一群人／一批零件：集会、装配',
  ),
  'assume': RootAnalysis(
    parts: [Morpheme.p('as', '向（ad-）'), Morpheme.r('sum', '拿（sumere）')],
    note: 'ad- + sumere「拿」→ 先拿过来当真的：假定、承担',
  ),
  'atom': RootAnalysis(
    parts: [Morpheme.p('a', '不'), Morpheme.r('tom', '切（希腊 temnein）')],
    note: 'a-「不」+ temnein「切」→ 不可再分的东西：原子',
  ),
  'atomic': RootAnalysis(
    parts: [
      Morpheme.p('a', '不'),
      Morpheme.r('tom', '切（temnein）'),
      Morpheme.s('ic', '形容词后缀'),
    ],
    note: '同 atom：不可再分的 → 原子的',
  ),
  'attempt': RootAnalysis(
    parts: [Morpheme.p('at', '向（ad-）'), Morpheme.r('tempt', '试（temptare）')],
    note: 'ad- + temptare「试」→ 朝目标试一把：尝试',
  ),
  'attribute': RootAnalysis(
    parts: [
      Morpheme.p('at', '向（ad-）'),
      Morpheme.r('tribut', '给予（tribuere）'),
      Morpheme.s('e', ''),
    ],
    note: 'ad- + tribuere「给予」→ 把性质归给某物：归因、属性',
  ),
  'autonomy': RootAnalysis(
    parts: [
      Morpheme.r('auto', '自己（希腊 autos）'),
      Morpheme.r('nom', '规则（希腊 nomos）'),
      Morpheme.s('y', '名词后缀'),
    ],
    note: 'autos「自己」+ nomos「法则」→ 自己给自己定规矩：自治',
  ),
  'avenue': RootAnalysis(
    parts: [
      Morpheme.p('a', '向（ad-）'),
      Morpheme.r('ven', '来（venire）'),
      Morpheme.s('ue', '名词后缀'),
    ],
    note: 'ad- + venire「来」→ 通往某处的路：大道、途径',
  ),
  'avert': RootAnalysis(
    parts: [Morpheme.p('a', '离开（ab-）'), Morpheme.r('vert', '转（vertere）')],
    note: 'ab- + vertere「转」→ 把脸转开：避免、转移',
  ),

  // ===== B =====
  'beggar': RootAnalysis(
    parts: [Morpheme.r('beg', '乞讨'), Morpheme.s('gar', '人（-er 的变体）')],
    note: 'beg「乞讨」→ 乞讨的人：乞丐',
  ),
  'bibliography': RootAnalysis(
    parts: [
      Morpheme.r('biblio', '书（希腊 biblion）'),
      Morpheme.r('graph', '写（希腊 graphein）'),
      Morpheme.s('y', '名词后缀'),
    ],
    note: 'biblion「书」+ graphein「写」→ 把书列出来：书目',
  ),
  'binary': RootAnalysis(
    parts: [Morpheme.r('bin', '二（bini）'), Morpheme.s('ary', '形容词后缀')],
    note: 'bini「两个一组」→ 二进制的、二元的',
  ),
  'brute': RootAnalysis(
    parts: [Morpheme.r('brut', '野兽（brutus）'), Morpheme.s('e', '')],
    note: '拉丁 brutus「野兽的、无理性的」→ 蛮力的人／兽',
  ),
  'brutal': RootAnalysis(
    parts: [Morpheme.r('brut', '野兽（brutus）'), Morpheme.s('al', '形容词后缀')],
    note: 'brutus「野兽的」→ 野兽般的：残忍的',
  ),
  'bundle': RootAnalysis(
    parts: [Morpheme.r('bund', '捆（bindan）'), Morpheme.s('le', '名词后缀')],
    note: 'bind「捆」→ 捆在一起的一束：捆、包',
  ),
  'bumper': RootAnalysis(
    parts: [Morpheme.r('bump', '撞'), Morpheme.s('er', '名词后缀')],
    note: 'bump「撞」+ -er → 用来挨撞的：保险杠',
  ),
  'bystander': RootAnalysis(
    parts: [
      Morpheme.p('by', '在旁边'),
      Morpheme.r('stand', '站'),
      Morpheme.s('er', '人'),
    ],
    note: 'by-「旁」+ stand「站」→ 站在旁边看的人：旁观者',
  ),

  // ===== C =====
  'caption': RootAnalysis(
    parts: [Morpheme.r('capt', '拿、抓（capere）'), Morpheme.s('ion', '名词后缀')],
    note: 'capere「拿」→ 抓住图片要点的文字：标题、字幕',
  ),
  'captive': RootAnalysis(
    parts: [Morpheme.r('capt', '抓（capere）'), Morpheme.s('ive', '形容词/名词后缀')],
    note: 'capere「抓」→ 被抓住的：俘虏',
  ),
  'cassette': RootAnalysis(
    parts: [Morpheme.r('cass', '盒子（cassa）'), Morpheme.s('ette', '小')],
    note: 'cassa「盒子」+ -ette「小」→ 小盒子：磁带盒',
  ),
  'cathedral': RootAnalysis(
    parts: [Morpheme.r('cathedr', '座椅（希腊 kathedra）'), Morpheme.s('al', '名词后缀')],
    note: 'kathedra「主教的座椅」→ 有大教堂座位的教堂：大教堂',
  ),
  'ceiling': RootAnalysis(
    parts: [Morpheme.r('ceil', '天花板（celare「藏」）'), Morpheme.s('ing', '名词后缀')],
    note: 'ceil 原义「给房间加盖藏起来」→ 天花板',
  ),
  'census': RootAnalysis(
    parts: [Morpheme.r('cens', '评估（censere）'), Morpheme.s('us', '名词后缀')],
    note: 'censere「估价、登记」→ 挨个登记人口：人口普查',
  ),
  'ceramic': RootAnalysis(
    parts: [Morpheme.r('ceram', '陶土（希腊 keramos）'), Morpheme.s('ic', '形容词后缀')],
    note: 'keramos「陶土」→ 陶瓷的',
  ),
  'cereal': RootAnalysis(
    parts: [Morpheme.r('cere', '谷物（Ceres 谷神）'), Morpheme.s('al', '名词后缀')],
    note: '来自谷物女神 Ceres → 谷类食物',
  ),
  'ceremonial': RootAnalysis(
    parts: [Morpheme.r('ceremon', '仪式'), Morpheme.s('ial', '形容词后缀')],
    note: 'ceremony「仪式」→ 礼仪性的',
  ),
  'charter': RootAnalysis(
    parts: [Morpheme.r('chart', '纸（希腊 chartēs）'), Morpheme.s('er', '名词后缀')],
    note: 'chartēs「纸」→ 写在纸上授予权利的文件：特许状、包租',
  ),
  'cherish': RootAnalysis(
    parts: [Morpheme.r('cher', '珍爱（法语 cher「珍贵」）'), Morpheme.s('ish', '动词后缀')],
    note: '古法语 cher「珍贵」→ 把某人某物看得珍贵：珍爱',
  ),
  'chronic': RootAnalysis(
    parts: [Morpheme.r('chron', '时间（希腊 chronos）'), Morpheme.s('ic', '形容词后缀')],
    note: 'chronos「时间」→ 拖很长时间的：慢性的',
  ),
  'circuit': RootAnalysis(
    parts: [Morpheme.r('circu', '环绕（circum）'), Morpheme.r('it', '走（ire）')],
    note: 'circum「绕」+ ire「走」→ 绕着走一圈：电路、巡回',
  ),
  'circulate': RootAnalysis(
    parts: [
      Morpheme.r('circul', '圆圈（circulus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'circulus「小圆圈」→ 绕圈流动：循环',
  ),
  'circumstance': RootAnalysis(
    parts: [Morpheme.p('circum', '周围'), Morpheme.r('stance', '站（stare）')],
    note: 'circum-「周围」+ stare「站」→ 站在周围的东西：环境、情形',
  ),
  'coincidence': RootAnalysis(
    parts: [
      Morpheme.p('co', '共同'),
      Morpheme.r('incid', '落下（incidere）'),
      Morpheme.s('ence', '名词后缀'),
    ],
    note: 'co- + incidere「落到一起」→ 两件事撞到一起：巧合',
  ),
  'collision': RootAnalysis(
    parts: [
      Morpheme.p('col', '共同（com-）'),
      Morpheme.r('lis', '撞（laedere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'com- + laedere「撞」→ 撞在一起：碰撞',
  ),
  'collar': RootAnalysis(
    parts: [Morpheme.r('coll', '脖子（collum）'), Morpheme.s('ar', '名词后缀')],
    note: 'collum「脖子」→ 围在脖子上的：衣领',
  ),
  'combat': RootAnalysis(
    parts: [Morpheme.p('com', '共同、相互'), Morpheme.r('bat', '打（battuere）')],
    note: 'com- + battuere「打」→ 对着打：战斗',
  ),
  'commend': RootAnalysis(
    parts: [Morpheme.p('com', '完全'), Morpheme.r('mend', '托付（mandare）')],
    note: 'com- + mandare「托付」→ 把人／事托付出去并说好话：称赞、推荐',
  ),
  'commerce': RootAnalysis(
    parts: [Morpheme.p('com', '共同'), Morpheme.r('merc', '交易（merx）')],
    note: 'com- + merx「货物」→ 货物互换：商业',
  ),
  'commercial': RootAnalysis(
    parts: [Morpheme.r('commerc', '交易（merx）'), Morpheme.s('ial', '形容词后缀')],
    note: 'commerce「商业」→ 商业的',
  ),
  'commute': RootAnalysis(
    parts: [Morpheme.p('com', '共同'), Morpheme.r('mut', '改变（mutare）')],
    note: 'com- + mutare「换」→ 来回换地方：通勤；也指减刑（把重刑换成轻刑）',
  ),
  'compatible': RootAnalysis(
    parts: [
      Morpheme.p('com', '共同'),
      Morpheme.r('pat', '感受、忍受（pati）'),
      Morpheme.s('ible', '能…的'),
    ],
    note: 'com- + pati「忍受」→ 能一起受得了的：兼容的',
  ),
  'compel': RootAnalysis(
    parts: [Morpheme.p('com', '完全'), Morpheme.r('pel', '推（pellere）')],
    note: 'com- + pellere「推」→ 一路推着走：强迫',
  ),
  'compensate': RootAnalysis(
    parts: [
      Morpheme.p('com', '共同'),
      Morpheme.r('pens', '称量、支付（pendere）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'com- + pendere「称量」→ 两边称平：补偿',
  ),
  'competent': RootAnalysis(
    parts: [
      Morpheme.p('com', '共同'),
      Morpheme.r('pet', '追求（petere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'com- + petere「追求」→ 追得上要求的：有能力的',
  ),
  'compliment': RootAnalysis(
    parts: [
      Morpheme.p('com', '完全'),
      Morpheme.r('pli', '填满（plere）'),
      Morpheme.s('ment', '名词后缀'),
    ],
    note: 'com- + plere「填满」→ 把礼仪做满：恭维、称赞',
  ),
  'compulsory': RootAnalysis(
    parts: [
      Morpheme.p('com', '完全'),
      Morpheme.r('puls', '推（pellere）'),
      Morpheme.s('ory', '形容词后缀'),
    ],
    note: 'com- + pellere「推」→ 被推着必须做的：强制的',
  ),
  'composure': RootAnalysis(
    parts: [
      Morpheme.p('com', '共同'),
      Morpheme.r('pos', '放（ponere）'),
      Morpheme.s('ure', '名词后缀'),
    ],
    note: 'com- + ponere「放」→ 心思都放稳了：镇定',
  ),
  'conceal': RootAnalysis(
    parts: [Morpheme.p('con', '完全'), Morpheme.r('ceal', '藏（celare）')],
    note: 'con- + celare「藏」→ 完全藏起来：隐瞒',
  ),
  'conceive': RootAnalysis(
    parts: [Morpheme.p('con', '完全'), Morpheme.r('ceive', '拿（capere）')],
    note: 'con- + capere「拿」→ 把想法接住：构想、怀孕',
  ),
  'concur': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('cur', '跑（currere）')],
    note: 'con- + currere「跑」→ 朝同一方向跑：同意、同时发生',
  ),
  'condense': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('dens', '密（densus）')],
    note: 'con- + densus「密」→ 压得更密：浓缩、凝结',
  ),
  'confer': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('fer', '带来（ferre）')],
    note: 'con- + ferre「带」→ 把意见带到一起：商议；把荣誉带给某人：授予',
  ),
  'confess': RootAnalysis(
    parts: [Morpheme.p('con', '完全'), Morpheme.r('fess', '说（fateri）')],
    note: 'con- + fateri「说」→ 全说出来：坦白',
  ),
  'consensus': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('sens', '感觉（sentire）'),
      Morpheme.s('us', '名词后缀'),
    ],
    note: 'con- + sentire「感觉」→ 感觉一致：共识',
  ),
  'consent': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('sent', '感觉（sentire）')],
    note: 'con- + sentire「感觉」→ 心里一致：同意',
  ),
  'conserve': RootAnalysis(
    parts: [Morpheme.p('con', '完全'), Morpheme.r('serv', '守护（servare）')],
    note: 'con- + servare「守护」→ 完整护住：保存、节约',
  ),
  'consolidate': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('solid', '坚固（solidus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'con- + solidus「坚固」→ 弄成一整块：巩固、合并',
  ),
  'conspicuous': RootAnalysis(
    parts: [
      Morpheme.p('con', '完全'),
      Morpheme.r('spic', '看（specere）'),
      Morpheme.s('uous', '形容词后缀'),
    ],
    note: 'con- + specere「看」→ 一眼就能看见：显眼的',
  ),
  'constituent': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('stitu', '建立、放置（statuere）'),
      Morpheme.s('ent', '后缀'),
    ],
    note: 'con- + statuere「立起来」→ 一起立成整体的部分：成分、选民',
  ),
  'constitution': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('stitut', '建立（statuere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'con- + statuere「立」→ 把国家立起来的东西：宪法、体质',
  ),
  'constrain': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('strain', '拉紧（stringere）')],
    note: 'con- + stringere「拉紧」→ 捆紧不让动：限制',
  ),
  'contaminate': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('tamin', '接触（tangere）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'con- + tangere「接触」→ 碰到一起被带脏：污染',
  ),
  'contemporary': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('tempor', '时间（tempus）'),
      Morpheme.s('ary', '形容词后缀'),
    ],
    note: 'con- + tempus「时间」→ 同一时间的：当代的、同时代的',
  ),
  'contemptible': RootAnalysis(
    parts: [
      Morpheme.p('con', '加强语气'),
      Morpheme.r('tempt', '轻视（temnere）'),
      Morpheme.s('ible', '能…的'),
    ],
    note: 'con- + temnere「轻视」→ 值得被轻视的：可鄙的',
  ),
  'contend': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('tend', '伸展（tendere）')],
    note: 'con- + tendere「伸」→ 各自把力气伸向同一目标：竞争、主张',
  ),
  'continent': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('tin', '保持（tenere）'),
      Morpheme.s('ent', '后缀'),
    ],
    note: 'con- + tenere「连成一片」→ 连着的大块陆地：大陆',
  ),
  'continental': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('tin', '保持（tenere）'),
      Morpheme.s('ental', '形容词后缀'),
    ],
    note: '同 continent：大陆的',
  ),
  'convention': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('vent', '来（venire）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'con- + venire「来」→ 大家走到一起定下的东西：惯例、大会',
  ),
  'convert': RootAnalysis(
    parts: [Morpheme.p('con', '完全'), Morpheme.r('vert', '转（vertere）')],
    note: 'con- + vertere「转」→ 整个转过来：转换、皈依',
  ),
  'converse': RootAnalysis(
    parts: [Morpheme.p('con', '共同'), Morpheme.r('vers', '转（vertere）')],
    note: 'con- + vertere「转」→ 你来我往地转：交谈；转过来的：相反的',
  ),
  'conversely': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('vers', '转（vertere）'),
      Morpheme.s('ely', '副词后缀'),
    ],
    note: '同 converse「相反的」+ -ly → 反过来（说）',
  ),
  'controversy': RootAnalysis(
    parts: [
      Morpheme.r('contro', '相反（contra）'),
      Morpheme.r('vers', '转（vertere）'),
      Morpheme.s('y', '名词后缀'),
    ],
    note: 'contra-「相反」+ vertere「转」→ 往相反方向转：争论',
  ),
  'controversial': RootAnalysis(
    parts: [
      Morpheme.r('contro', '相反（contra）'),
      Morpheme.r('vers', '转（vertere）'),
      Morpheme.s('ial', '形容词后缀'),
    ],
    note: '同 controversy：有争议的',
  ),
  'consecutive': RootAnalysis(
    parts: [
      Morpheme.p('con', '共同'),
      Morpheme.r('secut', '跟随（sequi）'),
      Morpheme.s('ive', '形容词后缀'),
    ],
    note: 'con- + sequi「跟随」→ 一个跟一个：连续的',
  ),
  'cordial': RootAnalysis(
    parts: [Morpheme.r('cord', '心（cor）'), Morpheme.s('ial', '形容词后缀')],
    note: 'cor「心」→ 发自内心的：热诚的',
  ),
  'corporate': RootAnalysis(
    parts: [Morpheme.r('corpor', '身体（corpus）'), Morpheme.s('ate', '形容词后缀')],
    note: 'corpus「身体」→ 结成一个整体的：公司的、法人的',
  ),
  'corporation': RootAnalysis(
    parts: [
      Morpheme.r('corpor', '身体（corpus）'),
      Morpheme.s('ation', '名词后缀'),
    ],
    note: 'corpus「身体」→ 结成一体的组织：公司、法人',
  ),
  'corrupt': RootAnalysis(
    parts: [Morpheme.p('cor', '完全（com-）'), Morpheme.r('rupt', '断（rumpere）')],
    note: 'com- + rumpere「断」→ 全烂断了：腐败的、贿赂',
  ),
  'cosmic': RootAnalysis(
    parts: [Morpheme.r('cosm', '宇宙（希腊 kosmos）'), Morpheme.s('ic', '形容词后缀')],
    note: 'kosmos「有秩序的宇宙」→ 宇宙的',
  ),
  'counterpart': RootAnalysis(
    parts: [Morpheme.p('counter', '对应、相对'), Morpheme.r('part', '部分')],
    note: 'counter-「对应」+ part「部分」→ 地位对应的一方：对应物',
  ),
  'coward': RootAnalysis(
    parts: [Morpheme.r('cow', '尾巴（古法语 coue）'), Morpheme.s('ard', '贬义人')],
    note: 'coue「尾巴」+ -ard → 夹着尾巴的人：胆小鬼',
  ),
  'cowardice': RootAnalysis(
    parts: [Morpheme.r('coward', '胆小鬼'), Morpheme.s('ice', '名词后缀')],
    note: 'coward「胆小鬼」+ -ice → 胆怯',
  ),
  'credible': RootAnalysis(
    parts: [Morpheme.r('cred', '相信（credere）'), Morpheme.s('ible', '能…的')],
    note: 'credere「相信」→ 可信的',
  ),
  'criterion': RootAnalysis(
    parts: [Morpheme.r('crit', '判断（希腊 krinein）'), Morpheme.s('erion', '工具')],
    note: 'krinein「判断」→ 用来判断的东西：标准',
  ),
  'cubic': RootAnalysis(
    parts: [Morpheme.r('cub', '立方（cubus）'), Morpheme.s('ic', '形容词后缀')],
    note: 'cubus「立方体」→ 立方的',
  ),
  'cultivate': RootAnalysis(
    parts: [
      Morpheme.r('cult', '耕种（colere）'),
      Morpheme.s('ivate', '动词后缀'),
    ],
    note: 'colere「耕种」→ 翻土培育：耕作、培养',
  ),
  'culminate': RootAnalysis(
    parts: [Morpheme.r('culmin', '顶点（culmen）'), Morpheme.s('ate', '动词后缀')],
    note: 'culmen「屋顶最高点」→ 到达顶点：达到高潮',
  ),
  'curriculum': RootAnalysis(
    parts: [Morpheme.r('curr', '跑（currere）'), Morpheme.s('iculum', '名词后缀')],
    note: 'currere「跑」→ 要跑完的路线：课程',
  ),
  'currency': RootAnalysis(
    parts: [Morpheme.r('curr', '跑、流通（currere）'), Morpheme.s('ency', '名词后缀')],
    note: 'currere「流通」→ 在市面上流通的东西：货币',
  ),
  'cursor': RootAnalysis(
    parts: [Morpheme.r('curs', '跑（currere）'), Morpheme.s('or', '者')],
    note: 'currere「跑」+ -or → 在屏幕上跑的东西：光标',
  ),
  'cynical': RootAnalysis(
    parts: [Morpheme.r('cyn', '狗（希腊 kyōn）'), Morpheme.s('ical', '形容词后缀')],
    note: '希腊犬儒学派（像狗一样活着）→ 不信人间有善意的：愤世嫉俗的',
  ),

  // ===== D =====
  'deceive': RootAnalysis(
    parts: [Morpheme.p('de', '离开、向下'), Morpheme.r('ceive', '拿（capere）')],
    note: 'de- + capere「拿」→ 把人拿偏了：欺骗',
  ),
  'deception': RootAnalysis(
    parts: [
      Morpheme.p('de', '离开、偏'),
      Morpheme.r('cept', '拿（capere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'de- + capere「拿」→ 拿歪了：欺骗、骗局',
  ),
  'declare': RootAnalysis(
    parts: [Morpheme.p('de', '完全'), Morpheme.r('clar', '清楚（clarus）')],
    note: 'de- + clarus「清楚」→ 说得清清楚楚：宣布',
  ),
  'deduct': RootAnalysis(
    parts: [Morpheme.p('de', '向下、离开'), Morpheme.r('duct', '引导（ducere）')],
    note: 'de- + ducere「引」→ 往下引走：扣除',
  ),
  'defect': RootAnalysis(
    parts: [Morpheme.p('de', '离开'), Morpheme.r('fect', '做（facere）')],
    note: 'de- + facere「做」→ 没做到位的地方：缺陷、叛逃',
  ),
  'deficient': RootAnalysis(
    parts: [
      Morpheme.p('de', '离开'),
      Morpheme.r('fic', '做（facere）'),
      Morpheme.s('ient', '形容词后缀'),
    ],
    note: 'de- + facere「做」→ 做得不够：缺乏的',
  ),
  'deficit': RootAnalysis(
    parts: [
      Morpheme.p('de', '离开'),
      Morpheme.r('fic', '做（facere）'),
      Morpheme.s('it', '名词后缀'),
    ],
    note: 'de- + facere「做」→ 该有的没做出来：赤字、缺口',
  ),
  'delegate': RootAnalysis(
    parts: [
      Morpheme.p('de', '向下'),
      Morpheme.r('leg', '派遣（legare）'),
      Morpheme.s('ate', '后缀'),
    ],
    note: 'de- + legare「派」→ 往下派：委派、代表',
  ),
  'deliberate': RootAnalysis(
    parts: [
      Morpheme.p('de', '完全'),
      Morpheme.r('liber', '称量（libra「天平」）'),
      Morpheme.s('ate', '后缀'),
    ],
    note: 'de- + libra「天平」→ 反复称量过的：深思熟虑的、故意的',
  ),
  'density': RootAnalysis(
    parts: [Morpheme.r('dens', '密（densus）'), Morpheme.s('ity', '名词后缀')],
    note: 'densus「密」→ 密度',
  ),
  'deposit': RootAnalysis(
    parts: [Morpheme.p('de', '向下'), Morpheme.r('pos', '放（ponere）')],
    note: 'de- + ponere「放」→ 往下放：存放、押金、沉积',
  ),
  'deprive': RootAnalysis(
    parts: [Morpheme.p('de', '离开'), Morpheme.r('priv', '个人的（privus）')],
    note: 'de- + privus「自己的」→ 把属于自己的拿走：剥夺',
  ),
  'destiny': RootAnalysis(
    parts: [
      Morpheme.p('de', '向下、定'),
      Morpheme.r('stin', '站定（stare）'),
      Morpheme.s('y', '名词后缀'),
    ],
    note: 'de- + stare「站定」→ 早就定好的位置：命运',
  ),
  'destruction': RootAnalysis(
    parts: [
      Morpheme.p('de', '向下、反'),
      Morpheme.r('struct', '建造（struere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'de- + struere「建」→ 把建的拆掉：破坏',
  ),
  'detach': RootAnalysis(
    parts: [Morpheme.p('de', '离开'), Morpheme.r('tach', '钉住、附着')],
    note: 'de- + tach「钉住」→ 把钉住的取下来：分离',
  ),
  'deteriorate': RootAnalysis(
    parts: [
      Morpheme.r('deterior', '更坏（拉丁 deterior）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'deterior「更坏的」→ 变坏：恶化',
  ),
  'devastate': RootAnalysis(
    parts: [
      Morpheme.p('de', '完全'),
      Morpheme.r('vast', '空（vastus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'de- + vastus「空」→ 弄成一片空：摧毁',
  ),
  'devour': RootAnalysis(
    parts: [Morpheme.p('de', '向下'), Morpheme.r('vour', '吞（vorare）')],
    note: 'de- + vorare「吞」→ 整个吞下去：吞噬',
  ),
  'dictate': RootAnalysis(
    parts: [Morpheme.r('dict', '说（dicere）'), Morpheme.s('ate', '动词后缀')],
    note: 'dicere「说」→ 说一句写一句：口述、命令',
  ),
  'diction': RootAnalysis(
    parts: [Morpheme.r('dict', '说（dicere）'), Morpheme.s('ion', '名词后缀')],
    note: 'dicere「说」→ 说话的方式：措辞',
  ),
  'dilute': RootAnalysis(
    parts: [Morpheme.p('di', '分开'), Morpheme.r('lu', '洗（lavare）')],
    note: 'dis- + lavare「洗」→ 加水冲开：稀释',
  ),
  'diminish': RootAnalysis(
    parts: [Morpheme.p('di', '向下'), Morpheme.r('min', '小（minus）'), Morpheme.s('ish', '动词后缀')],
    note: 'de- + minus「更小」→ 越变越小：减少',
  ),
  'discard': RootAnalysis(
    parts: [Morpheme.p('dis', '分开'), Morpheme.r('card', '纸牌')],
    note: 'dis- + card「牌」→ 把牌打出去：丢弃',
  ),
  'discern': RootAnalysis(
    parts: [Morpheme.p('dis', '分开'), Morpheme.r('cern', '筛、分辨（cernere）')],
    note: 'dis- + cernere「筛」→ 筛出来分清楚：辨别',
  ),
  'discourage': RootAnalysis(
    parts: [Morpheme.p('dis', '否定'), Morpheme.r('courage', '勇气')],
    note: 'dis-「去掉」+ courage「勇气」→ 使泄气：劝阻',
  ),
  'disguise': RootAnalysis(
    parts: [Morpheme.p('dis', '否定、改变'), Morpheme.r('guise', '外观')],
    note: 'dis- + guise「样子」→ 换了副样子：伪装',
  ),
  'disorder': RootAnalysis(
    parts: [Morpheme.p('dis', '否定'), Morpheme.r('order', '秩序')],
    note: 'dis-「无」+ order「秩序」→ 混乱、失调',
  ),
  'dispense': RootAnalysis(
    parts: [Morpheme.p('dis', '分开'), Morpheme.r('pens', '称量（pendere）')],
    note: 'dis- + pendere「称」→ 称好分出去：分发、配药；也指免除',
  ),
  'dispose': RootAnalysis(
    parts: [Morpheme.p('dis', '分开'), Morpheme.r('pos', '放（ponere）')],
    note: 'dis- + ponere「放」→ 分开放置：处理、布置',
  ),
  'disposition': RootAnalysis(
    parts: [
      Morpheme.p('dis', '分开'),
      Morpheme.r('posit', '放（ponere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'dis- + ponere「放」→ 心思被摆成的样子：性情、安排',
  ),
  'disposal': RootAnalysis(
    parts: [
      Morpheme.p('dis', '分开'),
      Morpheme.r('pos', '放（ponere）'),
      Morpheme.s('al', '名词后缀'),
    ],
    note: '同 dispose：处置、清理',
  ),
  'dissolve': RootAnalysis(
    parts: [Morpheme.p('dis', '分开'), Morpheme.r('solv', '松开（solvere）')],
    note: 'dis- + solvere「松开」→ 散开化掉：溶解、解散',
  ),
  'distinct': RootAnalysis(
    parts: [Morpheme.p('di', '分开'), Morpheme.r('stinct', '刺、标记（stinguere）')],
    note: 'dis- + stinguere「做标记」→ 标出来能分开：明显的、不同的',
  ),
  'distort': RootAnalysis(
    parts: [Morpheme.p('dis', '离开、反'), Morpheme.r('tort', '扭（torquere）')],
    note: 'dis- + torquere「扭」→ 扭歪：歪曲',
  ),
  'disturb': RootAnalysis(
    parts: [Morpheme.p('dis', '完全'), Morpheme.r('turb', '搅动（turbare）')],
    note: 'dis- + turbare「搅」→ 搅乱：打扰',
  ),
  'divorce': RootAnalysis(
    parts: [Morpheme.p('di', '分开'), Morpheme.r('vorc', '转（vertere）')],
    note: 'dis- + vertere「转」→ 各自转开：离婚',
  ),
  'domestic': RootAnalysis(
    parts: [Morpheme.r('dom', '家（domus）'), Morpheme.s('estic', '形容词后缀')],
    note: 'domus「家」→ 家里的、国内的',
  ),
  'domesticate': RootAnalysis(
    parts: [
      Morpheme.r('dom', '家（domus）'),
      Morpheme.s('esticate', '动词后缀'),
    ],
    note: 'domus「家」→ 把野的收进家：驯养',
  ),
  'dome': RootAnalysis(
    parts: [Morpheme.r('dom', '家、屋顶（domus）'), Morpheme.s('e', '')],
    note: 'domus「屋顶」→ 圆顶',
  ),
  'duple': RootAnalysis(
    parts: [Morpheme.r('du', '二（duo）'), Morpheme.r('ple', '倍（plicare）')],
    note: 'duo「二」+ plicare「折」→ 两倍的',
  ),

  // ===== E =====
  'eject': RootAnalysis(
    parts: [Morpheme.p('e', '向外'), Morpheme.r('ject', '扔（iacere）')],
    note: 'ex- + iacere「扔」→ 扔出去：喷射、驱逐',
  ),
  'elaborate': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('labor', '劳动（laborare）'),
      Morpheme.s('ate', '后缀'),
    ],
    note: 'ex- + laborare「干活」→ 下功夫做出来：精心制作的、详述',
  ),
  'elevate': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外、向上'),
      Morpheme.r('lev', '轻、举（levare）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + levare「举起」→ 举高：提升',
  ),
  'elite': RootAnalysis(
    parts: [Morpheme.p('e', '向外'), Morpheme.r('lit', '选（legere）')],
    note: 'ex- + legere「挑」→ 被挑出来的：精英',
  ),
  'eloquent': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('loqu', '说（loqui）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'ex- + loqui「说」→ 说出来有分量：雄辩的',
  ),
  'eliminate': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('limin', '门槛（limen）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + limen「门槛」→ 请出门外：淘汰、消除',
  ),
  'embark': RootAnalysis(
    parts: [Morpheme.p('em', '进入（in-）'), Morpheme.r('bark', '船（barca）')],
    note: 'in- + barca「船」→ 上船：登船、着手',
  ),
  'emit': RootAnalysis(
    parts: [Morpheme.p('e', '向外'), Morpheme.r('mit', '送（mittere）')],
    note: 'ex- + mittere「送」→ 送出去：发射、散发',
  ),
  'enforce': RootAnalysis(
    parts: [Morpheme.p('en', '使'), Morpheme.r('force', '力量（fortis）')],
    note: 'en-「使」+ force「力量」→ 使有力量：强制执行',
  ),
  'epidemic': RootAnalysis(
    parts: [
      Morpheme.p('epi', '在…之上'),
      Morpheme.r('dem', '人群（希腊 dēmos）'),
      Morpheme.s('ic', '后缀'),
    ],
    note: 'epi- + dēmos「民众」→ 在人群之上扩散：流行病',
  ),
  'epilepsy': RootAnalysis(
    parts: [
      Morpheme.p('epi', '在…之上'),
      Morpheme.r('lep', '抓（希腊 lambanein）'),
      Morpheme.s('sy', '名词后缀'),
    ],
    note: 'epi- + lambanein「抓」→ 突然被抓住：癫痫',
  ),
  'eradicate': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('radic', '根（radix）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + radix「根」→ 连根拔掉：根除',
  ),
  'erect': RootAnalysis(
    parts: [Morpheme.p('e', '向上'), Morpheme.r('rect', '直（regere）')],
    note: 'ex- + regere「弄直」→ 立直：竖立',
  ),
  'erosion': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('ros', '啃（rodere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'ex- + rodere「啃」→ 一点点啃掉：侵蚀',
  ),
  'essence': RootAnalysis(
    parts: [Morpheme.r('ess', '存在（esse）'), Morpheme.s('ence', '名词后缀')],
    note: '拉丁 esse「是、存在」→ 使某物成为它的东西：本质',
  ),
  'estate': RootAnalysis(
    parts: [Morpheme.p('e', '出'), Morpheme.r('stat', '站、状态（stare）'), Morpheme.s('e', '')],
    note: 'ex- + stare「站」→ 一个人所处的状况／占有的地：地产、庄园',
  ),
  'evaluate': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('valu', '价值（valere）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + valere「值」→ 把价值算出来：评估',
  ),
  'evaporate': RootAnalysis(
    parts: [
      Morpheme.p('e', '向外'),
      Morpheme.r('vapor', '蒸汽（vapor）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + vapor「汽」→ 变成汽跑掉：蒸发',
  ),
  'exaggerate': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('agger', '堆（agger「土堆」）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + agger「土堆」→ 往上堆：夸大',
  ),
  'exceed': RootAnalysis(
    parts: [Morpheme.p('ex', '超出'), Morpheme.r('ceed', '走（cedere）')],
    note: 'ex- + cedere「走」→ 走出界限：超过',
  ),
  'exclaim': RootAnalysis(
    parts: [Morpheme.p('ex', '向外'), Morpheme.r('claim', '喊（clamare）')],
    note: 'ex- + clamare「喊」→ 喊出来：惊叫',
  ),
  'exclusively': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('clus', '关（claudere）'),
      Morpheme.s('ively', '副词后缀'),
    ],
    note: 'ex- + claudere「关」→ 把别人关在外面：排他地、独占地',
  ),
  'execute': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外、到底'),
      Morpheme.r('secut', '跟随（sequi）'),
      Morpheme.s('e', ''),
    ],
    note: 'ex- + sequi「跟到底」→ 一路做完：执行、处决',
  ),
  'exert': RootAnalysis(
    parts: [Morpheme.p('ex', '向外'), Morpheme.r('ert', '放、伸（serere）')],
    note: 'ex- + serere「伸出去」→ 把力气使出去：施加',
  ),
  'exhaustive': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('haust', '抽（haurire）'),
      Morpheme.s('ive', '形容词后缀'),
    ],
    note: 'ex- + haurire「抽干」→ 抽到底的：详尽的',
  ),
  'exotic': RootAnalysis(
    parts: [Morpheme.r('exo', '外面（希腊 exō）'), Morpheme.s('tic', '形容词后缀')],
    note: 'exō「外面」→ 外来的：异域的',
  ),
  'expire': RootAnalysis(
    parts: [Morpheme.p('ex', '向外'), Morpheme.r('spire', '呼吸（spirare）')],
    note: 'ex- + spirare「呼吸」→ 呼出最后一口气：到期、断气',
  ),
  'explicit': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('plic', '折（plicare）'),
      Morpheme.s('it', '形容词后缀'),
    ],
    note: 'ex- + plicare「折」→ 摊开不折：明确的',
  ),
  'explicate': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('plic', '折（plicare）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'ex- + plicare「折」→ 把折着的摊开讲：详细解释',
  ),
  'explicitly': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('plic', '折（plicare）'),
      Morpheme.s('itly', '副词后缀'),
    ],
    note: '同 explicit：明确地',
  ),
  'explode': RootAnalysis(
    parts: [Morpheme.p('ex', '向外'), Morpheme.r('plod', '拍手（plaudere）')],
    note: 'ex- + plaudere「拍手」→ 台下把演员拍出去：爆炸；引申为爆开',
  ),
  'exquisite': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外、到底'),
      Morpheme.r('quisit', '寻求（quaerere）'),
      Morpheme.s('ite', '形容词后缀'),
    ],
    note: 'ex- + quaerere「找」→ 精挑细选出来的：精美的',
  ),
  'extinguish': RootAnalysis(
    parts: [
      Morpheme.p('ex', '向外'),
      Morpheme.r('tingu', '熄灭（stinguere）'),
      Morpheme.s('ish', '动词后缀'),
    ],
    note: 'ex- + stinguere「熄灭」→ 彻底灭掉：熄灭、消灭',
  ),
  'extravagant': RootAnalysis(
    parts: [
      Morpheme.p('extra', '超出'),
      Morpheme.r('vag', '游荡（vagari）'),
      Morpheme.s('ant', '形容词后缀'),
    ],
    note: 'extra- + vagari「乱走」→ 走出常规：奢侈的、过度的',
  ),

  // ===== F =====
  'facile': RootAnalysis(
    parts: [Morpheme.r('fac', '做（facere）'), Morpheme.s('ile', '易…的')],
    note: 'facere「做」→ 容易做的：轻率的、肤浅的',
  ),
  'faculty': RootAnalysis(
    parts: [Morpheme.r('facul', '能力（facultas）'), Morpheme.s('ty', '名词后缀')],
    note: 'facultas「能力」→ 能做事的本领：才能、系院',
  ),
  'faulty': RootAnalysis(
    parts: [Morpheme.r('fault', '缺陷（fallere「失误」）'), Morpheme.s('y', '形容词后缀')],
    note: 'fault「缺陷」→ 有毛病的',
  ),
  'feasible': RootAnalysis(
    parts: [Morpheme.r('feas', '做（facere）'), Morpheme.s('ible', '能…的')],
    note: 'facere「做」→ 做得成的：可行的',
  ),
  'federal': RootAnalysis(
    parts: [Morpheme.r('feder', '盟约（foedus）'), Morpheme.s('al', '形容词后缀')],
    note: 'foedus「盟约」→ 按盟约联结的：联邦的',
  ),
  'flourish': RootAnalysis(
    parts: [Morpheme.r('flor', '花（flos）'), Morpheme.s('ish', '动词后缀')],
    note: 'flos「花」→ 开花：繁荣、挥舞',
  ),
  'fluctuate': RootAnalysis(
    parts: [Morpheme.r('fluctu', '波（fluctus）'), Morpheme.s('ate', '动词后缀')],
    note: 'fluctus「波浪」→ 像波浪一样上下：波动',
  ),
  'fluid': RootAnalysis(
    parts: [Morpheme.r('flu', '流（fluere）'), Morpheme.s('id', '形容词后缀')],
    note: 'fluere「流」→ 流动的：流体',
  ),
  'forceful': RootAnalysis(
    parts: [Morpheme.r('force', '力量'), Morpheme.s('ful', '充满…的')],
    note: 'force「力量」→ 有力的',
  ),
  'formidable': RootAnalysis(
    parts: [Morpheme.r('formid', '恐惧（formido）'), Morpheme.s('able', '可…的')],
    note: 'formido「恐惧」→ 让人害怕的：强大的、可怕的',
  ),
  'fort': RootAnalysis(
    parts: [Morpheme.r('fort', '强（fortis）'), Morpheme.s('t', '')],
    note: 'fortis「强」→ 加固的地方：堡垒',
  ),
  'fountain': RootAnalysis(
    parts: [Morpheme.r('fount', '泉（fons）'), Morpheme.s('ain', '名词后缀')],
    note: 'fons「泉」→ 泉、喷泉',
  ),
  'franchise': RootAnalysis(
    parts: [Morpheme.r('franch', '自由（franc）'), Morpheme.s('ise', '名词后缀')],
    note: 'franc「自由」→ 授予的自由／特权：特许经营权',
  ),

  // ===== G =====
  'garage': RootAnalysis(
    parts: [Morpheme.r('gar', '存放（古法语 garer）'), Morpheme.s('age', '场所')],
    note: 'garer「停放」+ -age「场所」→ 停车的地方：车库',
  ),
  'gastronomic': RootAnalysis(
    parts: [
      Morpheme.r('gastro', '胃（希腊 gastēr）'),
      Morpheme.r('nom', '法则（nomos）'),
      Morpheme.s('ic', '形容词后缀'),
    ],
    note: 'gastēr「胃」+ nomos「法则」→ 关于吃的讲究：美食的',
  ),
  'generalize': RootAnalysis(
    parts: [Morpheme.r('general', '一般（genus「种类」）'), Morpheme.s('ize', '使…化')],
    note: 'genus「种类」→ 归到某一类：概括',
  ),
  'geometry': RootAnalysis(
    parts: [
      Morpheme.r('geo', '土地（希腊 gē）'),
      Morpheme.r('metr', '测量（metron）'),
      Morpheme.s('y', '学科后缀'),
    ],
    note: 'gē「地」+ metron「量」→ 量地之学：几何',
  ),
  'gigantic': RootAnalysis(
    parts: [Morpheme.r('gigant', '巨人（希腊 gigas）'), Morpheme.s('ic', '形容词后缀')],
    note: 'gigas「巨人」→ 巨大的',
  ),
  'grieve': RootAnalysis(
    parts: [Morpheme.r('griev', '重（gravis）'), Morpheme.s('e', '')],
    note: 'gravis「重」→ 心里压着石头：悲伤',
  ),
  'grief': RootAnalysis(
    parts: [Morpheme.r('grie', '重（gravis）'), Morpheme.s('f', '名词后缀')],
    note: '同 grieve：压在心里的重：悲痛',
  ),

  // ===== H =====
  'handicap': RootAnalysis(
    parts: [Morpheme.r('hand', '手'), Morpheme.r('i', ''), Morpheme.r('cap', '帽子')],
    note: 'hand in cap：旧时抽签游戏把手伸进帽子取罚则 → 障碍、不利条件',
  ),
  'hardware': RootAnalysis(
    parts: [Morpheme.r('hard', '硬'), Morpheme.r('ware', '器件')],
    note: 'hard「硬」+ ware「器件」→ 硬件',
  ),
  'hardship': RootAnalysis(
    parts: [Morpheme.r('hard', '艰难'), Morpheme.s('ship', '状态')],
    note: 'hard「艰难」+ -ship「状态」→ 艰难处境',
  ),
  'hatred': RootAnalysis(
    parts: [Morpheme.r('hate', '恨'), Morpheme.s('red', '古英语「状态」后缀')],
    note: 'hate「恨」+ 古英语 -rǣden「状态」→ 憎恨',
  ),
  'heedless': RootAnalysis(
    parts: [Morpheme.r('heed', '注意'), Morpheme.s('less', '无…的')],
    note: 'heed「留意」+ -less「无」→ 不在意的',
  ),
  'hemisphere': RootAnalysis(
    parts: [Morpheme.p('hemi', '半'), Morpheme.r('sphere', '球（希腊 sphaira）')],
    note: 'hemi-「半」+ sphaira「球」→ 半球',
  ),
  'homogeneous': RootAnalysis(
    parts: [
      Morpheme.r('homo', '相同（希腊 homos）'),
      Morpheme.r('gene', '种类（genos）'),
      Morpheme.s('ous', '形容词后缀'),
    ],
    note: 'homos「同」+ genos「种类」→ 同类的：均质的',
  ),
  'hypothesis': RootAnalysis(
    parts: [Morpheme.p('hypo', '在下面'), Morpheme.r('thesis', '放置（希腊 thesis）')],
    note: 'hypo-「下」+ thesis「放」→ 放在下面当基础的说法：假设',
  ),
  'hypothesize': RootAnalysis(
    parts: [
      Morpheme.p('hypo', '在下面'),
      Morpheme.r('thes', '放置（希腊 thesis）'),
      Morpheme.s('ize', '动词后缀'),
    ],
    note: '同 hypothesis：提出假设',
  ),

  // ===== I =====
  'illuminate': RootAnalysis(
    parts: [
      Morpheme.p('il', '向内、加强（in-）'),
      Morpheme.r('lumin', '光（lumen）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'in- + lumen「光」→ 照进光：照亮、阐明',
  ),
  'illusion': RootAnalysis(
    parts: [
      Morpheme.p('il', '向内（in-）'),
      Morpheme.r('lus', '玩、戏弄（ludere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'in- + ludere「戏弄」→ 被眼睛戏弄：错觉',
  ),
  'immune': RootAnalysis(
    parts: [Morpheme.p('im', '不'), Morpheme.r('mun', '公共义务（munus）'), Morpheme.s('e', '')],
    note: 'in-「不」+ munus「义务」→ 不用承担：免疫的、免除的',
  ),
  'impair': RootAnalysis(
    parts: [Morpheme.p('im', '使…变'), Morpheme.r('pair', '更坏（pejor）')],
    note: 'in- + pejor「更坏」→ 使变坏：损害',
  ),
  'implication': RootAnalysis(
    parts: [
      Morpheme.p('im', '向内'),
      Morpheme.r('plic', '折（plicare）'),
      Morpheme.s('ation', '名词后缀'),
    ],
    note: 'in- + plicare「折」→ 折在话里的东西：含义、牵连',
  ),
  'implicit': RootAnalysis(
    parts: [
      Morpheme.p('im', '向内'),
      Morpheme.r('plic', '折（plicare）'),
      Morpheme.s('it', '形容词后缀'),
    ],
    note: 'in- + plicare「折」→ 折在里面没摊开：含蓄的',
  ),
  'impulse': RootAnalysis(
    parts: [Morpheme.p('im', '向内'), Morpheme.r('puls', '推（pellere）')],
    note: 'in- + pellere「推」→ 从里面推一下：冲动、脉冲',
  ),
  'impulsive': RootAnalysis(
    parts: [
      Morpheme.p('im', '向内'),
      Morpheme.r('puls', '推（pellere）'),
      Morpheme.s('ive', '形容词后缀'),
    ],
    note: 'in- + pellere「推」→ 被推着就动：冲动的',
  ),
  'impose': RootAnalysis(
    parts: [Morpheme.p('im', '在上'), Morpheme.r('pos', '放（ponere）')],
    note: 'in- + ponere「放」→ 压在上面放：强加、征税',
  ),
  'inaugurate': RootAnalysis(
    parts: [
      Morpheme.p('in', '在内'),
      Morpheme.r('augur', '占卜（augur）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'in- + augur「占卜」→ 先占卜再上任：就职、开创',
  ),
  'incline': RootAnalysis(
    parts: [Morpheme.p('in', '向'), Morpheme.r('clin', '倾斜（clinare）')],
    note: 'in- + clinare「斜」→ 向一边斜：倾向、倾斜',
  ),
  'indicator': RootAnalysis(
    parts: [
      Morpheme.p('in', '向'),
      Morpheme.r('dic', '指、说（dicere）'),
      Morpheme.s('ator', '名词后缀'),
    ],
    note: 'in- + dicere「指」→ 指出来的东西：指示器、指标',
  ),
  'indigenous': RootAnalysis(
    parts: [
      Morpheme.p('indi', '在内（indu-）'),
      Morpheme.r('gen', '出生（gignere）'),
      Morpheme.s('ous', '形容词后缀'),
    ],
    note: 'indu-「在内」+ gignere「生」→ 生在本地的：土著的',
  ),
  'indignant': RootAnalysis(
    parts: [
      Morpheme.p('in', '不'),
      Morpheme.r('dign', '值得（dignus）'),
      Morpheme.s('ant', '形容词后缀'),
    ],
    note: 'in-「不」+ dignus「值得」→ 觉得不配这样被对待：愤怒的',
  ),
  'induce': RootAnalysis(
    parts: [Morpheme.p('in', '向内'), Morpheme.r('duc', '引导（ducere）')],
    note: 'in- + ducere「引」→ 往里引：诱导、引起',
  ),
  'industrious': RootAnalysis(
    parts: [Morpheme.r('industri', '勤勉（industria）'), Morpheme.s('ous', '形容词后缀')],
    note: 'industria「勤勉」→ 勤奋的',
  ),
  'inevitable': RootAnalysis(
    parts: [
      Morpheme.p('in', '不'),
      Morpheme.r('evit', '避开（evitare）'),
      Morpheme.s('able', '可…的'),
    ],
    note: 'in-「不」+ evitare「避开」→ 躲不掉的：必然的',
  ),
  'inferior': RootAnalysis(
    parts: [Morpheme.r('infer', '下面的（inferus）'), Morpheme.s('ior', '比较级后缀')],
    note: 'inferus「下面的」→ 较低的、较差的',
  ),
  'infinite': RootAnalysis(
    parts: [Morpheme.p('in', '不'), Morpheme.r('fin', '界限（finis）'), Morpheme.s('ite', '形容词后缀')],
    note: 'in-「不」+ finis「界限」→ 没有边界的：无限的',
  ),
  'inflation': RootAnalysis(
    parts: [
      Morpheme.p('in', '向内'),
      Morpheme.r('flat', '吹（flare）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'in- + flare「吹」→ 吹胀：通货膨胀',
  ),
  'influenza': RootAnalysis(
    parts: [
      Morpheme.p('in', '进入'),
      Morpheme.r('flu', '流（fluere）'),
      Morpheme.s('enza', '名词后缀'),
    ],
    note: 'in- + fluere「流」→ 星象「流入」人间的影响：流感',
  ),
  'ingenuity': RootAnalysis(
    parts: [
      Morpheme.p('in', '在内'),
      Morpheme.r('genu', '天生（gignere）'),
      Morpheme.s('ity', '名词后缀'),
    ],
    note: 'in- + gignere「生」→ 天生带在身上的本事：巧妙、独创',
  ),
  'initiative': RootAnalysis(
    parts: [
      Morpheme.p('in', '进入'),
      Morpheme.r('it', '走（ire）'),
      Morpheme.s('iative', '名词后缀'),
    ],
    note: 'in- + ire「走」→ 先走进去的那一步：主动性、倡议',
  ),
  'inquire': RootAnalysis(
    parts: [Morpheme.p('in', '向内'), Morpheme.r('quir', '寻求（quaerere）')],
    note: 'in- + quaerere「找」→ 往里追问：询问、调查',
  ),
  'insert': RootAnalysis(
    parts: [Morpheme.p('in', '进入'), Morpheme.r('sert', '插（serere）')],
    note: 'in- + serere「插接」→ 插进去：插入',
  ),
  'instalment': RootAnalysis(
    parts: [
      Morpheme.p('in', '在内'),
      Morpheme.r('stal', '位置（stallum）'),
      Morpheme.s('ment', '名词后缀'),
    ],
    note: 'in- + stallum「位置」→ 把款项一次次放到位：分期付款',
  ),
  'instinct': RootAnalysis(
    parts: [Morpheme.p('in', '在内'), Morpheme.r('stinct', '刺、驱使（stinguere）')],
    note: 'in- + stinguere「刺」→ 内在被刺一下的反应：本能',
  ),
  'institution': RootAnalysis(
    parts: [
      Morpheme.p('in', '在内'),
      Morpheme.r('stitut', '建立（statuere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'in- + statuere「立」→ 立起来的规矩／组织：制度、机构',
  ),
  'instruct': RootAnalysis(
    parts: [Morpheme.p('in', '在内'), Morpheme.r('struct', '建造（struere）')],
    note: 'in- + struere「堆建」→ 在人脑子里搭起结构：指导、命令',
  ),
  'insurance': RootAnalysis(
    parts: [
      Morpheme.p('in', '使'),
      Morpheme.r('sur', '在上、确保（securus）'),
      Morpheme.s('ance', '名词后缀'),
    ],
    note: 'in- + assure「使确定」→ 把风险变成确定：保险',
  ),
  'intact': RootAnalysis(
    parts: [Morpheme.p('in', '不'), Morpheme.r('tact', '触碰（tangere）')],
    note: 'in-「不」+ tangere「碰」→ 没被碰过的：完好无损的',
  ),
  'intellect': RootAnalysis(
    parts: [Morpheme.p('inter', '在…之间'), Morpheme.r('lect', '选、读（legere）')],
    note: 'inter- + legere「选」→ 在事物之间辨选的能力：智力',
  ),
  'interfere': RootAnalysis(
    parts: [Morpheme.p('inter', '在…之间'), Morpheme.r('fere', '打、撞（ferire）')],
    note: 'inter- + ferire「打」→ 插到中间去撞：干涉',
  ),
  'interior': RootAnalysis(
    parts: [Morpheme.p('inter', '在…之内'), Morpheme.s('ior', '比较级后缀')],
    note: 'inter「在内」+ -ior → 更靠里的：内部的',
  ),
  'intermittent': RootAnalysis(
    parts: [
      Morpheme.p('inter', '在…之间'),
      Morpheme.r('mitt', '送（mittere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'inter- + mittere「送」→ 中间断一下再来：间歇的',
  ),
  'interrogate': RootAnalysis(
    parts: [
      Morpheme.p('inter', '在…之间'),
      Morpheme.r('rog', '问（rogare）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'inter- + rogare「问」→ 反复盘问：审讯',
  ),
  'interval': RootAnalysis(
    parts: [Morpheme.p('inter', '在…之间'), Morpheme.r('val', '墙、壁垒（vallum）')],
    note: 'inter- + vallum「墙」→ 两墙之间的一段：间隔',
  ),
  'intimacy': RootAnalysis(
    parts: [Morpheme.r('intim', '最内的（intimus）'), Morpheme.s('acy', '名词后缀')],
    note: 'intimus「最里面的」→ 亲近、私密',
  ),
  'intimidate': RootAnalysis(
    parts: [
      Morpheme.p('in', '使'),
      Morpheme.r('timid', '害怕（timidus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'in- + timidus「胆怯」→ 使人害怕：威胁',
  ),
  'intoxicate': RootAnalysis(
    parts: [
      Morpheme.p('in', '在内'),
      Morpheme.r('toxic', '毒（toxicum）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'in- + toxicum「毒」→ 毒进了身体：使醉、使陶醉',
  ),
  'intrigue': RootAnalysis(
    parts: [Morpheme.p('in', '在内'), Morpheme.r('trig', '纠缠（tricae）')],
    note: 'in- + tricae「纠缠」→ 绕进去：密谋；把人绕住：激起兴趣',
  ),
  'intuition': RootAnalysis(
    parts: [
      Morpheme.p('in', '向内'),
      Morpheme.r('tuit', '看（tueri）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'in- + tueri「看」→ 往里一看就懂：直觉',
  ),
  'invade': RootAnalysis(
    parts: [Morpheme.p('in', '进入'), Morpheme.r('vad', '走（vadere）')],
    note: 'in- + vadere「走」→ 走进去：入侵',
  ),
  'invasive': RootAnalysis(
    parts: [
      Morpheme.p('in', '进入'),
      Morpheme.r('vas', '走（vadere）'),
      Morpheme.s('ive', '形容词后缀'),
    ],
    note: 'in- + vadere「走」→ 往里走的：侵入的',
  ),
  'inventory': RootAnalysis(
    parts: [
      Morpheme.p('in', '在内'),
      Morpheme.r('vent', '来（venire）'),
      Morpheme.s('ory', '名词后缀'),
    ],
    note: 'in- + venire「来」→ 进来的东西逐项记下：清单、库存',
  ),
  'invigorate': RootAnalysis(
    parts: [
      Morpheme.p('in', '使'),
      Morpheme.r('vigor', '活力（vigere）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'in- + vigor「活力」→ 使有劲：使振奋',
  ),

  // ===== J =====
  'junction': RootAnalysis(
    parts: [Morpheme.r('junct', '连接（iungere）'), Morpheme.s('ion', '名词后缀')],
    note: 'iungere「连接」→ 接合处：路口、枢纽',
  ),

  // ===== L =====
  'labor': RootAnalysis(
    parts: [Morpheme.r('labor', '劳动（laborare）'), Morpheme.s('', '')],
    note: '拉丁 labor「劳作」→ 劳动',
  ),
  'laminate': RootAnalysis(
    parts: [Morpheme.r('lamin', '薄片（lamina）'), Morpheme.s('ate', '动词后缀')],
    note: 'lamina「薄片」→ 压成薄片：层压',
  ),
  'landlord': RootAnalysis(
    parts: [Morpheme.r('land', '土地'), Morpheme.r('lord', '主人')],
    note: 'land「地」+ lord「主」→ 地主、房东',
  ),
  'latitude': RootAnalysis(
    parts: [Morpheme.r('lat', '宽（latus）'), Morpheme.s('itude', '名词后缀')],
    note: 'latus「宽」→ 地图上的宽度：纬度；（行动的）余地',
  ),
  'laundry': RootAnalysis(
    parts: [Morpheme.r('launder', '洗（lavare）'), Morpheme.s('y', '名词后缀')],
    note: 'launder「洗」→ 洗衣、待洗衣物',
  ),
  'layman': RootAnalysis(
    parts: [Morpheme.r('lay', '世俗的'), Morpheme.r('man', '人')],
    note: 'lay「非神职、外行」+ man「人」→ 门外汉',
  ),
  'layoff': RootAnalysis(
    parts: [Morpheme.r('lay', '放'), Morpheme.r('off', '离开')],
    note: 'lay off「放下、让人离开」→ 裁员',
  ),
  'layer': RootAnalysis(
    parts: [Morpheme.r('lay', '放、铺'), Morpheme.s('er', '名词后缀')],
    note: 'lay「铺」+ -er → 铺上去的一层：层',
  ),
  'lease': RootAnalysis(
    parts: [Morpheme.r('leas', '放开（laissier）'), Morpheme.s('e', '')],
    note: '古法语 laissier「放手让别人用」→ 出租、租约',
  ),
  'legalese': RootAnalysis(
    parts: [Morpheme.r('legal', '法律的（lex）'), Morpheme.s('ese', '行话后缀')],
    note: 'legal「法律的」+ -ese「行话」→ 法律行话',
  ),
  'legislate': RootAnalysis(
    parts: [
      Morpheme.r('legis', '法律（lex）'),
      Morpheme.r('lat', '带来（ferre）'),
      Morpheme.s('e', ''),
    ],
    note: 'lex「法」+ latus「带」→ 把法条带出来：立法',
  ),
  'liable': RootAnalysis(
    parts: [Morpheme.r('li', '捆绑（ligare）'), Morpheme.s('able', '可…的')],
    note: 'ligare「绑」→ 被绑住要负责的：有责任的、易于…的',
  ),
  'liberal': RootAnalysis(
    parts: [Morpheme.r('liber', '自由（liber）'), Morpheme.s('al', '形容词后缀')],
    note: 'liber「自由」→ 自由的、开明的',
  ),
  'literacy': RootAnalysis(
    parts: [Morpheme.r('liter', '文字（littera）'), Morpheme.s('acy', '名词后缀')],
    note: 'littera「字母」→ 认字的能力：读写能力',
  ),
  'likewise': RootAnalysis(
    parts: [Morpheme.r('like', '相同'), Morpheme.r('wise', '方式')],
    note: 'like「相同」+ wise「方式」→ 同样地',
  ),

  // ===== M =====
  'magnificent': RootAnalysis(
    parts: [
      Morpheme.r('magn', '大（magnus）'),
      Morpheme.r('fic', '做（facere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'magnus「大」+ facere「做」→ 做得很大：壮丽的',
  ),
  'majesty': RootAnalysis(
    parts: [Morpheme.r('maj', '大（maius）'), Morpheme.s('esty', '名词后缀')],
    note: 'maius「更大」→ 至高无上：威严、陛下',
  ),
  'manipulate': RootAnalysis(
    parts: [
      Morpheme.r('mani', '手（manus）'),
      Morpheme.r('pul', '填、握（plere）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'manus「手」+ plere「握满」→ 用手摆弄：操纵',
  ),
  'manifest': RootAnalysis(
    parts: [Morpheme.r('mani', '手（manus）'), Morpheme.r('fest', '抓、碰（fendere）')],
    note: 'manus「手」+ 抓 → 手能抓住的：明显的；清单',
  ),
  'manual': RootAnalysis(
    parts: [Morpheme.r('manu', '手（manus）'), Morpheme.s('al', '形容词后缀')],
    note: 'manus「手」→ 用手做的：手工的；手册',
  ),
  'manufacture': RootAnalysis(
    parts: [
      Morpheme.r('manu', '手（manus）'),
      Morpheme.r('fact', '做（facere）'),
      Morpheme.s('ure', '名词后缀'),
    ],
    note: 'manus「手」+ facere「做」→ 用手做出来：制造',
  ),
  'margin': RootAnalysis(
    parts: [Morpheme.r('marg', '边（margo）'), Morpheme.s('in', '名词后缀')],
    note: 'margo「边缘」→ 页边、利润空间',
  ),
  'masculine': RootAnalysis(
    parts: [Morpheme.r('mascul', '男性（mas）'), Morpheme.s('ine', '形容词后缀')],
    note: 'mas「男人」→ 男性的',
  ),
  'mayor': RootAnalysis(
    parts: [Morpheme.r('may', '大（maior）'), Morpheme.s('or', '人')],
    note: 'maior「更大」→ 城里更大的人物：市长',
  ),
  'meditating': RootAnalysis(
    parts: [Morpheme.r('medit', '思考（meditari）'), Morpheme.s('ating', '分词后缀')],
    note: 'meditari「反复思量」→ 沉思、冥想（现在分词）',
  ),
  'menace': RootAnalysis(
    parts: [Morpheme.r('men', '突出、威胁（minere）'), Morpheme.s('ace', '名词后缀')],
    note: 'minere「突出、逼人」→ 悬在头上的威胁',
  ),
  'mercury': RootAnalysis(
    parts: [Morpheme.r('merc', '商品（merx）'), Morpheme.s('ury', '名词后缀')],
    note: 'Mercurius 商神 → 水银；水星',
  ),
  'meteor': RootAnalysis(
    parts: [Morpheme.r('meteor', '高空现象（希腊 meteōron）'), Morpheme.s('', '')],
    note: '希腊 meteōron「天上的东西」→ 流星',
  ),
  'meteoric': RootAnalysis(
    parts: [Morpheme.r('meteor', '流星'), Morpheme.s('ic', '形容词后缀')],
    note: 'meteor「流星」→ 流星般的：迅疾的',
  ),
  'metric': RootAnalysis(
    parts: [Morpheme.r('metr', '测量（希腊 metron）'), Morpheme.s('ic', '形容词后缀')],
    note: 'metron「量」→ 度量的、公制的',
  ),
  'misaligned': RootAnalysis(
    parts: [Morpheme.p('mis', '错误'), Morpheme.r('aligned', '对齐')],
    note: 'mis-「错」+ align「对齐」→ 没对齐的',
  ),
  'miserable': RootAnalysis(
    parts: [Morpheme.r('miser', '悲惨（miser）'), Morpheme.s('able', '形容词后缀')],
    note: 'miser「可怜」→ 悲惨的',
  ),
  'misery': RootAnalysis(
    parts: [Morpheme.r('miser', '悲惨（miser）'), Morpheme.s('y', '名词后缀')],
    note: 'miser「可怜」→ 苦难',
  ),
  'moisture': RootAnalysis(
    parts: [Morpheme.r('moist', '湿'), Morpheme.s('ure', '名词后缀')],
    note: 'moist「湿」→ 湿气、水分',
  ),
  'molecule': RootAnalysis(
    parts: [Morpheme.r('mole', '团块（moles）'), Morpheme.s('cule', '小')],
    note: 'moles「块」+ -cule「小」→ 小团块：分子',
  ),
  'molecular': RootAnalysis(
    parts: [Morpheme.r('mole', '团块（moles）'), Morpheme.s('cular', '形容词后缀')],
    note: '同 molecule：分子的',
  ),
  'mortgage': RootAnalysis(
    parts: [Morpheme.r('mort', '死（mors）'), Morpheme.r('gage', '抵押')],
    note: 'mort「死」+ gage「抵押」→ 债务结束时抵押失效：按揭',
  ),
  'mount': RootAnalysis(
    parts: [Morpheme.r('mont', '山（mons）'), Morpheme.s('', '')],
    note: 'mons「山」→ 登山、上升；也指坐骑',
  ),

  // ===== N =====
  'narcissistic': RootAnalysis(
    parts: [Morpheme.r('narciss', '水仙（希腊 Narkissos）'), Morpheme.s('istic', '形容词后缀')],
    note: '爱上自己水中倒影的那喀索斯 → 自恋的',
  ),
  'narrative': RootAnalysis(
    parts: [Morpheme.r('narr', '讲述（narrare）'), Morpheme.s('ative', '形容词/名词后缀')],
    note: 'narrare「讲」→ 叙事的、叙述',
  ),
  'narrate': RootAnalysis(
    parts: [Morpheme.r('narr', '讲述（narrare）'), Morpheme.s('ate', '动词后缀')],
    note: 'narrare「讲」→ 讲述',
  ),
  'native': RootAnalysis(
    parts: [Morpheme.r('nat', '出生（nasci）'), Morpheme.s('ive', '形容词后缀')],
    note: 'nasci「出生」→ 出生地的：本地的',
  ),
  'negate': RootAnalysis(
    parts: [Morpheme.r('neg', '否定（negare）'), Morpheme.s('ate', '动词后缀')],
    note: 'negare「否认」→ 否定',
  ),
  'negligible': RootAnalysis(
    parts: [
      Morpheme.r('neg', '不（nec）'),
      Morpheme.r('lig', '挑选（legere）'),
      Morpheme.s('ible', '可…的'),
    ],
    note: 'nec-「不」+ legere「挑」→ 不值得挑的：可忽略的',
  ),
  'notorious': RootAnalysis(
    parts: [Morpheme.r('not', '知道（notus）'), Morpheme.s('orious', '形容词后缀')],
    note: 'notus「已知的」→ 出了名的（多指坏名声）',
  ),
  'novelty': RootAnalysis(
    parts: [Morpheme.r('novel', '新（novus）'), Morpheme.s('ty', '名词后缀')],
    note: 'novus「新」→ 新奇、新奇事物',
  ),
  'nuance': RootAnalysis(
    parts: [Morpheme.r('nu', '云（nubes）'), Morpheme.s('ance', '名词后缀')],
    note: 'nubes「云」→ 云影般的细微差别：细微之处',
  ),
  'nutrient': RootAnalysis(
    parts: [Morpheme.r('nutri', '滋养（nutrire）'), Morpheme.s('ent', '后缀')],
    note: 'nutrire「养」→ 养分',
  ),

  // ===== O =====
  'obedient': RootAnalysis(
    parts: [
      Morpheme.p('ob', '向'),
      Morpheme.r('edi', '听（audire）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'ob- + audire「听」→ 朝着对方听：顺从的',
  ),
  'obstacle': RootAnalysis(
    parts: [Morpheme.p('ob', '对着'), Morpheme.r('sta', '站（stare）'), Morpheme.s('cle', '名词后缀')],
    note: 'ob- + stare「站」→ 挡在对面站着的东西：障碍',
  ),
  'occasion': RootAnalysis(
    parts: [
      Morpheme.p('oc', '向（ob-）'),
      Morpheme.r('cas', '落下（cadere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'ob- + cadere「落」→ 落到眼前的时机：场合、时机',
  ),
  'offend': RootAnalysis(
    parts: [Morpheme.p('of', '对着（ob-）'), Morpheme.r('fend', '撞、打（fendere）')],
    note: 'ob- + fendere「打」→ 撞上去：冒犯、犯罪',
  ),
  'orbit': RootAnalysis(
    parts: [Morpheme.r('orb', '圆圈（orbis）'), Morpheme.s('it', '名词后缀')],
    note: 'orbis「圆环」→ 绕圈的轨道',
  ),
  'orient': RootAnalysis(
    parts: [Morpheme.r('ori', '升起（oriri）'), Morpheme.s('ent', '名词后缀')],
    note: 'oriri「太阳升起」→ 太阳升起的方向：东方；定方向',
  ),
  'oval': RootAnalysis(
    parts: [Morpheme.r('ov', '卵（ovum）'), Morpheme.s('al', '形容词后缀')],
    note: 'ovum「蛋」→ 蛋形的：椭圆',
  ),
  'overtake': RootAnalysis(
    parts: [Morpheme.p('over', '超过'), Morpheme.r('take', '拿、取')],
    note: 'over-「越过」+ take「取」→ 从后面超过：赶上、追上',
  ),

  // ===== P =====
  'pandemic': RootAnalysis(
    parts: [
      Morpheme.p('pan', '全部（希腊 pan）'),
      Morpheme.r('dem', '人群（dēmos）'),
      Morpheme.s('ic', '后缀'),
    ],
    note: 'pan-「全」+ dēmos「民众」→ 波及所有人的：大流行',
  ),
  'paradigm': RootAnalysis(
    parts: [Morpheme.p('para', '在旁'), Morpheme.r('digm', '展示（deiknynai）')],
    note: 'para- + deiknynai「展示」→ 摆在旁边给人看的样板：范式',
  ),
  'particle': RootAnalysis(
    parts: [Morpheme.r('part', '部分'), Morpheme.s('icle', '小')],
    note: 'part「部分」+ -icle「小」→ 小部分：微粒、小品词',
  ),
  'peculiar': RootAnalysis(
    parts: [Morpheme.r('peculi', '私产（peculium）'), Morpheme.s('ar', '形容词后缀')],
    note: 'peculium「私有钱财」→ 只属于某人的：特有的、奇怪的',
  ),
  'pension': RootAnalysis(
    parts: [Morpheme.r('pens', '称量、支付（pendere）'), Morpheme.s('ion', '名词后缀')],
    note: 'pendere「称量支付」→ 按期付出的钱：养老金',
  ),
  'pentatonic': RootAnalysis(
    parts: [
      Morpheme.r('penta', '五（希腊 pente）'),
      Morpheme.r('ton', '音（tonos）'),
      Morpheme.s('ic', '形容词后缀'),
    ],
    note: 'pente「五」+ tonos「音」→ 五声音阶的',
  ),
  'perceive': RootAnalysis(
    parts: [Morpheme.p('per', '彻底'), Morpheme.r('ceive', '拿（capere）')],
    note: 'per- + capere「拿」→ 彻底抓住：察觉、理解',
  ),
  'perception': RootAnalysis(
    parts: [
      Morpheme.p('per', '彻底'),
      Morpheme.r('cept', '拿（capere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'per- + capere「拿」→ 抓住外界信息：知觉、看法',
  ),
  'permanent': RootAnalysis(
    parts: [
      Morpheme.p('per', '贯穿'),
      Morpheme.r('man', '停留（manere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'per- + manere「停留」→ 一直停在那儿：永久的',
  ),
  'perplexity': RootAnalysis(
    parts: [
      Morpheme.p('per', '彻底'),
      Morpheme.r('plex', '编织（plectere）'),
      Morpheme.s('ity', '名词后缀'),
    ],
    note: 'per- + plectere「编」→ 被彻底缠住：困惑',
  ),
  'perspective': RootAnalysis(
    parts: [
      Morpheme.p('per', '透过'),
      Morpheme.r('spect', '看（specere）'),
      Morpheme.s('ive', '后缀'),
    ],
    note: 'per- + specere「看」→ 透过某处看过去：视角',
  ),
  'periodic': RootAnalysis(
    parts: [
      Morpheme.p('peri', '周围'),
      Morpheme.r('od', '路（希腊 hodos）'),
      Morpheme.s('ic', '形容词后缀'),
    ],
    note: 'peri- + hodos「路」→ 绕一圈回来：周期的',
  ),
  'pivotal': RootAnalysis(
    parts: [Morpheme.r('pivot', '枢轴'), Morpheme.s('al', '形容词后缀')],
    note: 'pivot「枢轴」→ 像轴一样关键的',
  ),
  'plagued': RootAnalysis(
    parts: [Morpheme.r('plague', '瘟疫'), Morpheme.s('ed', '形容词后缀')],
    note: 'plague「瘟疫」→ 被灾祸缠住的：饱受困扰的',
  ),
  'plausible': RootAnalysis(
    parts: [Morpheme.r('plaus', '拍手（plaudere）'), Morpheme.s('ible', '可…的')],
    note: 'plaudere「拍手」→ 值得鼓掌的：说得通的',
  ),
  'possess': RootAnalysis(
    parts: [Morpheme.p('pos', '能（potis）'), Morpheme.r('sess', '坐（sedere）')],
    note: 'potis「能」+ sedere「坐」→ 能坐得住的：拥有',
  ),
  'postpone': RootAnalysis(
    parts: [Morpheme.p('post', '之后'), Morpheme.r('pon', '放（ponere）')],
    note: 'post- + ponere「放」→ 往后放：推迟',
  ),
  'postulate': RootAnalysis(
    parts: [Morpheme.r('postul', '要求（postulare）'), Morpheme.s('ate', '后缀')],
    note: 'postulare「要求」→ 先要求承认的前提：假定',
  ),
  'pottery': RootAnalysis(
    parts: [Morpheme.r('potter', '陶工'), Morpheme.s('y', '名词后缀')],
    note: 'potter「陶工」→ 陶器',
  ),
  'prayer': RootAnalysis(
    parts: [Morpheme.r('pray', '祈祷（precari）'), Morpheme.s('er', '名词后缀')],
    note: 'precari「恳求」→ 祈祷',
  ),
  'precede': RootAnalysis(
    parts: [Morpheme.p('pre', '在前'), Morpheme.r('cede', '走（cedere）')],
    note: 'pre- + cedere「走」→ 走在前头：先于',
  ),
  'preliminary': RootAnalysis(
    parts: [
      Morpheme.p('pre', '在前'),
      Morpheme.r('limin', '门槛（limen）'),
      Morpheme.s('ary', '形容词后缀'),
    ],
    note: 'pre- + limen「门槛」→ 进门槛之前的：初步的',
  ),
  'premature': RootAnalysis(
    parts: [Morpheme.p('pre', '提前'), Morpheme.r('matur', '成熟（maturus）')],
    note: 'pre- + maturus「熟」→ 还没熟就来了：过早的',
  ),
  'preoccupation': RootAnalysis(
    parts: [Morpheme.p('pre', '预先'), Morpheme.r('occupation', '占据')],
    note: 'pre-「先」+ occupy「占据」→ 心先被占住：全神贯注之事',
  ),
  'preserve': RootAnalysis(
    parts: [Morpheme.p('pre', '预先'), Morpheme.r('serv', '守护（servare）')],
    note: 'pre- + servare「守护」→ 提前护住：保存',
  ),
  'prestigious': RootAnalysis(
    parts: [Morpheme.r('prestig', '幻术、威望（praestigiae）'), Morpheme.s('ious', '形容词后缀')],
    note: '原指障眼法，后转指让人眩目的名声 → 有声望的',
  ),
  'prevalent': RootAnalysis(
    parts: [
      Morpheme.p('pre', '在前'),
      Morpheme.r('val', '强壮（valere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'pre- + valere「强」→ 势力最强的：流行的',
  ),
  'prevail': RootAnalysis(
    parts: [Morpheme.p('pre', '在前'), Morpheme.r('vail', '强（valere）')],
    note: 'pre- + valere「强」→ 强过对方：占优势、盛行',
  ),
  'primitive': RootAnalysis(
    parts: [Morpheme.r('prim', '第一（primus）'), Morpheme.s('itive', '形容词后缀')],
    note: 'primus「最初」→ 最初的：原始的',
  ),
  'principal': RootAnalysis(
    parts: [Morpheme.r('princip', '首位（princeps）'), Morpheme.s('al', '形容词后缀')],
    note: 'princeps「第一个」→ 首要的：校长、本金',
  ),
  'private': RootAnalysis(
    parts: [Morpheme.r('priv', '个人的（privus）'), Morpheme.s('ate', '形容词后缀')],
    note: 'privus「个人的」→ 私人的',
  ),
  'proceed': RootAnalysis(
    parts: [Morpheme.p('pro', '向前'), Morpheme.r('ceed', '走（cedere）')],
    note: 'pro- + cedere「走」→ 往前走：继续进行',
  ),
  'procession': RootAnalysis(
    parts: [
      Morpheme.p('pro', '向前'),
      Morpheme.r('cess', '走（cedere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'pro- + cedere「走」→ 往前走的一队人：队伍、游行',
  ),
  'proceeding': RootAnalysis(
    parts: [
      Morpheme.p('pro', '向前'),
      Morpheme.r('ceed', '走（cedere）'),
      Morpheme.s('ing', '名词后缀'),
    ],
    note: 'pro- + cedere「走」→ 正在推进的事：诉讼程序、事项',
  ),
  'proclaim': RootAnalysis(
    parts: [Morpheme.p('pro', '向前、公开'), Morpheme.r('claim', '喊（clamare）')],
    note: 'pro- + clamare「喊」→ 当众喊出来：宣告',
  ),
  'proficient': RootAnalysis(
    parts: [
      Morpheme.p('pro', '向前'),
      Morpheme.r('fic', '做（facere）'),
      Morpheme.s('ient', '形容词后缀'),
    ],
    note: 'pro- + facere「做」→ 往前做出成果：熟练的',
  ),
  'profound': RootAnalysis(
    parts: [Morpheme.p('pro', '向下、向前'), Morpheme.r('found', '底（fundus）')],
    note: 'pro- + fundus「底」→ 到底的：深刻的',
  ),
  'prominent': RootAnalysis(
    parts: [
      Morpheme.p('pro', '向前'),
      Morpheme.r('min', '突出（minere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'pro- + minere「突出」→ 往前凸出来的：突出的、知名的',
  ),
  'promise': RootAnalysis(
    parts: [
      Morpheme.p('pro', '向前'),
      Morpheme.r('mis', '送（mittere）'),
      Morpheme.s('e', ''),
    ],
    note: 'pro- + mittere「送」→ 把话先送出去：承诺',
  ),
  'propagate': RootAnalysis(
    parts: [
      Morpheme.r('prop', '后代（propago）'),
      Morpheme.r('ag', '做（agere）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'propago「压条繁殖」→ 一代代繁殖、传播',
  ),
  'property': RootAnalysis(
    parts: [Morpheme.r('propri', '自己的（proprius）'), Morpheme.s('ety', '名词后缀')],
    note: 'proprius「自己的」→ 属于自己的东西：财产、性质',
  ),
  'propriety': RootAnalysis(
    parts: [Morpheme.r('propri', '自己的（proprius）'), Morpheme.s('ety', '名词后缀')],
    note: 'proprius「自己的」→ 合乎本分的：得体、礼节',
  ),
  'prospect': RootAnalysis(
    parts: [Morpheme.p('pro', '向前'), Morpheme.r('spect', '看（specere）')],
    note: 'pro- + specere「看」→ 往前看：前景',
  ),
  'protest': RootAnalysis(
    parts: [Morpheme.p('pro', '公开、向前'), Morpheme.r('test', '见证（testis）')],
    note: 'pro- + testis「见证」→ 当众作证反对：抗议',
  ),
  'provoke': RootAnalysis(
    parts: [Morpheme.p('pro', '向前'), Morpheme.r('vok', '叫（vocare）')],
    note: 'pro- + vocare「叫」→ 冲着人喊：挑衅、激起',
  ),
  'prudent': RootAnalysis(
    parts: [Morpheme.r('prud', '谨慎（prudens）'), Morpheme.s('ent', '形容词后缀')],
    note: 'providens「预先看见」的缩略 → 审慎的',
  ),
  'prudence': RootAnalysis(
    parts: [Morpheme.r('prud', '谨慎（prudens）'), Morpheme.s('ence', '名词后缀')],
    note: '同 prudent：审慎',
  ),
  'publicize': RootAnalysis(
    parts: [Morpheme.r('public', '公共（publicus）'), Morpheme.s('ize', '使…化')],
    note: 'public「公共」+ -ize → 让大家都知道：宣传',
  ),
  'punctual': RootAnalysis(
    parts: [Morpheme.r('punct', '点（punctum）'), Morpheme.s('ual', '形容词后缀')],
    note: 'punctum「点」→ 卡在点上：准时的',
  ),
  'punch': RootAnalysis(
    parts: [Morpheme.r('punct', '刺（pungere）'), Morpheme.s('', '')],
    note: 'pungere「刺」→ 用拳头／工具打孔：拳打、打孔',
  ),
  'punish': RootAnalysis(
    parts: [Morpheme.r('pun', '惩罚（poena）'), Morpheme.s('ish', '动词后缀')],
    note: 'poena「罚金、惩罚」→ 惩罚',
  ),

  // ===== Q =====
  'quarantine': RootAnalysis(
    parts: [Morpheme.r('quarant', '四十（quaranta）'), Morpheme.s('ine', '名词后缀')],
    note: '威尼斯规定外来船只需隔离四十天 → 隔离检疫',
  ),

  // ===== R =====
  'radiate': RootAnalysis(
    parts: [Morpheme.r('radi', '光线（radius）'), Morpheme.s('ate', '动词后缀')],
    note: 'radius「光线、辐条」→ 向外发光：辐射',
  ),
  'radical': RootAnalysis(
    parts: [Morpheme.r('radic', '根（radix）'), Morpheme.s('al', '形容词后缀')],
    note: 'radix「根」→ 从根上来的：根本的、激进的',
  ),
  'radically': RootAnalysis(
    parts: [Morpheme.r('radic', '根（radix）'), Morpheme.s('ally', '副词后缀')],
    note: 'radix「根」→ 从根本上',
  ),
  'radius': RootAnalysis(
    parts: [Morpheme.r('radi', '辐条、光线（radius）'), Morpheme.s('us', '名词后缀')],
    note: 'radius「车轮辐条」→ 从圆心射出的线段：半径',
  ),
  'rational': RootAnalysis(
    parts: [Morpheme.r('ration', '理性（ratio）'), Morpheme.s('al', '形容词后缀')],
    note: 'ratio「计算、理性」→ 讲道理的：理性的',
  ),
  'recede': RootAnalysis(
    parts: [Morpheme.p('re', '向后'), Morpheme.r('cede', '走（cedere）')],
    note: 're- + cedere「走」→ 往后退：后退、减弱',
  ),
  'reception': RootAnalysis(
    parts: [
      Morpheme.p('re', '回'),
      Morpheme.r('cept', '拿（capere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 're- + capere「拿」→ 接住来的人／信号：接待、接收',
  ),
  'recession': RootAnalysis(
    parts: [
      Morpheme.p('re', '向后'),
      Morpheme.r('cess', '走（cedere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 're- + cedere「走」→ 往后退：衰退',
  ),
  'recipe': RootAnalysis(
    parts: [Morpheme.p('re', '再'), Morpheme.r('cip', '拿（capere）'), Morpheme.s('e', '')],
    note: 're- + capere「拿」→ 照单再取一次：处方、食谱',
  ),
  'reclaim': RootAnalysis(
    parts: [Morpheme.p('re', '回'), Morpheme.r('claim', '喊、要求（clamare）')],
    note: 're- + clamare「喊」→ 喊回来：取回、开垦',
  ),
  'reconcile': RootAnalysis(
    parts: [
      Morpheme.p('re', '再'),
      Morpheme.r('con', '共同'),
      Morpheme.r('cil', '召集（calare）'),
      Morpheme.s('e', ''),
    ],
    note: 're- + con- + calare「召集」→ 再叫到一起：使和解',
  ),
  'referee': RootAnalysis(
    parts: [
      Morpheme.p('re', '回'),
      Morpheme.r('fer', '带（ferre）'),
      Morpheme.s('ee', '被…的人'),
    ],
    note: 're- + ferre「带」+ -ee → 被请去裁定的人：裁判',
  ),
  'refine': RootAnalysis(
    parts: [Morpheme.p('re', '再'), Morpheme.r('fine', '精细（finis）')],
    note: 're- + fine「精细」→ 再加工变精：提炼、改进',
  ),
  'refuge': RootAnalysis(
    parts: [Morpheme.p('re', '向后'), Morpheme.r('fug', '逃（fugere）')],
    note: 're- + fugere「逃」→ 逃回去的地方：避难所',
  ),
  'refugee': RootAnalysis(
    parts: [
      Morpheme.p('re', '向后'),
      Morpheme.r('fug', '逃（fugere）'),
      Morpheme.s('ee', '人'),
    ],
    note: 're- + fugere「逃」+ -ee → 逃难的人：难民',
  ),
  'refute': RootAnalysis(
    parts: [Morpheme.p('re', '反'), Morpheme.r('fut', '打（futare）')],
    note: 're- + futare「打」→ 打回去：反驳',
  ),
  'regulate': RootAnalysis(
    parts: [Morpheme.r('regul', '规则（regula）'), Morpheme.s('ate', '动词后缀')],
    note: 'regula「尺子、规则」→ 按规矩管：调节',
  ),
  'reinforce': RootAnalysis(
    parts: [
      Morpheme.p('re', '再'),
      Morpheme.p('in', '进入'),
      Morpheme.r('force', '力量'),
    ],
    note: 're- + in- + force「力量」→ 再加一层力：加强',
  ),
  'rejoice': RootAnalysis(
    parts: [Morpheme.p('re', '再、加强'), Morpheme.r('joice', '高兴（joie）')],
    note: 're- + 古法语 joie「快乐」→ 非常高兴：欣喜',
  ),
  'rejuvenate': RootAnalysis(
    parts: [
      Morpheme.p('re', '再'),
      Morpheme.r('juven', '年轻（juvenis）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 're- + juvenis「年轻」→ 使再年轻：恢复活力',
  ),
  'relay': RootAnalysis(
    parts: [Morpheme.p('re', '再'), Morpheme.r('lay', '放')],
    note: 're- + lay「放」→ 换一拨人再放上去：接力、转播',
  ),
  'reluctant': RootAnalysis(
    parts: [
      Morpheme.p('re', '反'),
      Morpheme.r('luct', '挣扎（luctari）'),
      Morpheme.s('ant', '形容词后缀'),
    ],
    note: 're- + luctari「挣扎」→ 反着挣扎：不情愿的',
  ),
  'remain': RootAnalysis(
    parts: [Morpheme.p('re', '向后'), Morpheme.r('main', '停留（manere）')],
    note: 're- + manere「停留」→ 留在原处：剩下、保持',
  ),
  'remedy': RootAnalysis(
    parts: [Morpheme.p('re', '再'), Morpheme.r('med', '医治（mederi）'), Morpheme.s('y', '名词后缀')],
    note: 're- + mederi「医治」→ 再治好：补救办法',
  ),
  'renovate': RootAnalysis(
    parts: [
      Morpheme.p('re', '再'),
      Morpheme.r('nov', '新（novus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 're- + novus「新」→ 使重新变新：翻修',
  ),
  'reproach': RootAnalysis(
    parts: [Morpheme.p('re', '回'), Morpheme.r('proach', '靠近（prope）')],
    note: 're- + prope「近」→ 凑近了指责：责备',
  ),
  'reservoir': RootAnalysis(
    parts: [
      Morpheme.p('re', '回'),
      Morpheme.r('serv', '守护（servare）'),
      Morpheme.s('oir', '场所'),
    ],
    note: 're- + servare「存」→ 把水存起来的地方：水库',
  ),
  'resolution': RootAnalysis(
    parts: [
      Morpheme.p('re', '回、再'),
      Morpheme.r('solut', '松开（solvere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 're- + solvere「松开」→ 把结解开：决心、决议、分辨率',
  ),
  'resonate': RootAnalysis(
    parts: [
      Morpheme.p('re', '回'),
      Morpheme.r('son', '声音（sonus）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 're- + sonus「声」→ 回声共振：引起共鸣',
  ),
  'resort': RootAnalysis(
    parts: [Morpheme.p('re', '再'), Morpheme.r('sort', '命运、种类（sors）')],
    note: 're- + sors「命运」→ 又回到那处去：求助、胜地',
  ),
  'resume': RootAnalysis(
    parts: [Morpheme.p('re', '再'), Morpheme.r('sum', '拿（sumere）')],
    note: 're- + sumere「拿」→ 再拿起来：继续、简历',
  ),
  'retreat': RootAnalysis(
    parts: [Morpheme.p('re', '向后'), Morpheme.r('treat', '拉（trahere）')],
    note: 're- + trahere「拉」→ 往回拉：撤退、静修',
  ),
  'retrospect': RootAnalysis(
    parts: [Morpheme.p('retro', '向后'), Morpheme.r('spect', '看（specere）')],
    note: 'retro- + specere「看」→ 回头看：回顾',
  ),
  'reverse': RootAnalysis(
    parts: [Morpheme.p('re', '向后'), Morpheme.r('vers', '转（vertere）')],
    note: 're- + vertere「转」→ 反过来转：颠倒、倒退',
  ),
  'rigid': RootAnalysis(
    parts: [Morpheme.r('rig', '僵硬（rigere）'), Morpheme.s('id', '形容词后缀')],
    note: 'rigere「冻硬」→ 硬的、死板的',
  ),
  'rival': RootAnalysis(
    parts: [Morpheme.r('riv', '河岸（rivus）'), Morpheme.s('al', '名词后缀')],
    note: 'rivalis 指「共用一条河的人」→ 争同一份资源的人：对手',
  ),
  'rotate': RootAnalysis(
    parts: [Morpheme.r('rot', '轮子（rota）'), Morpheme.s('ate', '动词后缀')],
    note: 'rota「轮」→ 像轮子一样转：旋转',
  ),
  'rupture': RootAnalysis(
    parts: [Morpheme.r('rupt', '断（rumpere）'), Morpheme.s('ure', '名词后缀')],
    note: 'rumpere「断」→ 断裂、破裂',
  ),

  // ===== S =====
  'sacrifice': RootAnalysis(
    parts: [
      Morpheme.r('sacri', '神圣（sacer）'),
      Morpheme.r('fic', '做（facere）'),
      Morpheme.s('e', ''),
    ],
    note: 'sacer「神圣」+ facere「做」→ 把东西献给神：牺牲',
  ),
  'salute': RootAnalysis(
    parts: [Morpheme.r('salut', '健康（salus）'), Morpheme.s('e', '')],
    note: 'salus「健康」→ 祝对方安好：敬礼、致意',
  ),
  'saucer': RootAnalysis(
    parts: [Morpheme.r('sauc', '酱汁（salsa）'), Morpheme.s('er', '器皿')],
    note: 'sauce「酱汁」+ -er → 盛酱汁的小碟：茶碟',
  ),
  'scheme': RootAnalysis(
    parts: [Morpheme.r('schem', '形状（希腊 schēma）'), Morpheme.s('e', '')],
    note: 'schēma「形状、图形」→ 图纸、方案、阴谋',
  ),
  'script': RootAnalysis(
    parts: [Morpheme.r('script', '写（scribere）'), Morpheme.s('', '')],
    note: 'scribere「写」→ 写下来的东西：剧本、文字',
  ),
  'scrutiny': RootAnalysis(
    parts: [Morpheme.r('scrut', '翻查（scrutari）'), Morpheme.s('iny', '名词后缀')],
    note: 'scrutari「翻检破烂」→ 仔细翻查：细看',
  ),
  'sector': RootAnalysis(
    parts: [Morpheme.r('sect', '切（secare）'), Morpheme.s('or', '名词后缀')],
    note: 'secare「切」→ 切出来的一块：部门、扇形',
  ),
  'seduce': RootAnalysis(
    parts: [Morpheme.p('se', '离开'), Morpheme.r('duc', '引导（ducere）')],
    note: 'se- + ducere「引」→ 引到一边去：引诱',
  ),
  'segment': RootAnalysis(
    parts: [Morpheme.r('seg', '切（secare）'), Morpheme.s('ment', '名词后缀')],
    note: 'secare「切」→ 切下的一段：片段',
  ),
  'segregate': RootAnalysis(
    parts: [
      Morpheme.p('se', '分开'),
      Morpheme.r('greg', '群（grex）'),
      Morpheme.s('ate', '动词后缀'),
    ],
    note: 'se- + grex「群」→ 从群里分出去：隔离',
  ),
  'seminar': RootAnalysis(
    parts: [Morpheme.r('semin', '种子（semen）'), Morpheme.s('ar', '名词后缀')],
    note: 'semen「种子」→ 播撒想法的小课：研讨课',
  ),
  'semiconductor': RootAnalysis(
    parts: [
      Morpheme.p('semi', '半'),
      Morpheme.r('conduct', '传导'),
      Morpheme.s('or', '名词后缀'),
    ],
    note: 'semi-「半」+ conduct「传导」→ 导电性介于两者之间：半导体',
  ),
  'sensible': RootAnalysis(
    parts: [Morpheme.r('sens', '感觉（sentire）'), Morpheme.s('ible', '可…的')],
    note: 'sentire「感觉」→ 能感觉到的、想得通的：明智的',
  ),
  'sentiment': RootAnalysis(
    parts: [
      Morpheme.r('sent', '感觉（sentire）'),
      Morpheme.s('iment', '名词后缀'),
    ],
    note: 'sentire「感觉」→ 情感、看法',
  ),
  'sequence': RootAnalysis(
    parts: [Morpheme.r('sequ', '跟随（sequi）'), Morpheme.s('ence', '名词后缀')],
    note: 'sequi「跟随」→ 一个跟一个：顺序、序列',
  ),
  'setback': RootAnalysis(
    parts: [Morpheme.r('set', '放'), Morpheme.r('back', '向后')],
    note: 'set back「往回放」→ 往后退的一步：挫折',
  ),
  'shutter': RootAnalysis(
    parts: [Morpheme.r('shut', '关闭'), Morpheme.s('ter', '器具')],
    note: 'shut「关」+ -ter → 能关上的板：百叶窗、快门',
  ),
  'singular': RootAnalysis(
    parts: [Morpheme.r('singul', '单个（singulus）'), Morpheme.s('ar', '形容词后缀')],
    note: 'singulus「一个」→ 单数的、非凡的',
  ),
  'sophistication': RootAnalysis(
    parts: [
      Morpheme.r('soph', '智慧（希腊 sophos）'),
      Morpheme.s('istication', '名词后缀'),
    ],
    note: 'sophos「智慧」→ 精明老练、复杂精细',
  ),
  'sovereign': RootAnalysis(
    parts: [Morpheme.r('sover', '在上（super）'), Morpheme.r('reign', '统治（regnare）')],
    note: 'super「在上」+ regnare「统治」→ 最高统治者：君主、主权的',
  ),
  'spatial': RootAnalysis(
    parts: [Morpheme.r('spati', '空间（spatium）'), Morpheme.s('al', '形容词后缀')],
    note: 'spatium「空间」→ 空间的',
  ),
  'specify': RootAnalysis(
    parts: [Morpheme.r('speci', '种类（species）'), Morpheme.s('fy', '使…')],
    note: 'species「种类」→ 把种类说清：具体指明',
  ),
  'spectacle': RootAnalysis(
    parts: [Morpheme.r('spect', '看（specere）'), Morpheme.s('acle', '名词后缀')],
    note: 'specere「看」→ 给人看的东西：景象、眼镜（复数）',
  ),
  'speculate': RootAnalysis(
    parts: [Morpheme.r('specul', '观察（specula「瞭望台」）'), Morpheme.s('ate', '动词后缀')],
    note: 'specula「瞭望台」→ 远望猜测：推测、投机',
  ),
  'splendid': RootAnalysis(
    parts: [Morpheme.r('splend', '发光（splendere）'), Morpheme.s('id', '形容词后缀')],
    note: 'splendere「发光」→ 光辉灿烂的',
  ),
  'spontaneous': RootAnalysis(
    parts: [Morpheme.r('sponte', '自愿（sponte）'), Morpheme.s('aneous', '形容词后缀')],
    note: 'sponte「自愿」→ 自己冒出来的：自发的',
  ),
  'spouse': RootAnalysis(
    parts: [Morpheme.r('spous', '承诺（spondere）'), Morpheme.s('e', '')],
    note: 'spondere「立誓」→ 立过誓的人：配偶',
  ),
  'stadium': RootAnalysis(
    parts: [Morpheme.r('stad', '站、长度单位（stadion）'), Morpheme.s('ium', '场所')],
    note: '希腊 stadion 是跑道长度 → 跑道围起来的地方：体育场',
  ),
  'static': RootAnalysis(
    parts: [Morpheme.r('sta', '站（stare）'), Morpheme.s('tic', '形容词后缀')],
    note: 'stare「站」→ 站着不动的：静态的、静电',
  ),
  'statute': RootAnalysis(
    parts: [Morpheme.r('statut', '立定（statuere）'), Morpheme.s('e', '')],
    note: 'statuere「立」→ 立起来的条文：法规',
  ),
  'stigma': RootAnalysis(
    parts: [Morpheme.r('stig', '刺、烙印（stigma）'), Morpheme.s('ma', '名词后缀')],
    note: '希腊 stigma「烙在奴隶身上的印记」→ 耻辱的标记',
  ),
  'steroid': RootAnalysis(
    parts: [Morpheme.r('ster', '固（希腊 stereos）'), Morpheme.s('oid', '似…的')],
    note: 'stereos「固体的」+ -oid「类似」→ 类固醇',
  ),
  'subsequent': RootAnalysis(
    parts: [
      Morpheme.p('sub', '随后'),
      Morpheme.r('sequ', '跟随（sequi）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'sub- + sequi「跟随」→ 跟着来的：随后的',
  ),
  'subsequently': RootAnalysis(
    parts: [
      Morpheme.p('sub', '随后'),
      Morpheme.r('sequ', '跟随（sequi）'),
      Morpheme.s('ently', '副词后缀'),
    ],
    note: '同 subsequent：随后地',
  ),
  'subscribe': RootAnalysis(
    parts: [Morpheme.p('sub', '在下面'), Morpheme.r('scrib', '写（scribere）')],
    note: 'sub- + scribere「写」→ 在下面签字：订阅、同意',
  ),
  'substitute': RootAnalysis(
    parts: [
      Morpheme.p('sub', '代替、下面'),
      Morpheme.r('stitut', '放置（statuere）'),
      Morpheme.s('e', ''),
    ],
    note: 'sub- + statuere「放」→ 放到那个位子上：代替、替代品',
  ),
  'subtract': RootAnalysis(
    parts: [Morpheme.p('sub', '向下、去掉'), Morpheme.r('tract', '拉（trahere）')],
    note: 'sub- + trahere「拉」→ 往下拉走：减去',
  ),
  'succession': RootAnalysis(
    parts: [
      Morpheme.p('suc', '下面（sub-）'),
      Morpheme.r('cess', '走（cedere）'),
      Morpheme.s('ion', '名词后缀'),
    ],
    note: 'sub- + cedere「走」→ 一个接一个走上来：连续、继承',
  ),
  'successive': RootAnalysis(
    parts: [
      Morpheme.p('suc', '下面（sub-）'),
      Morpheme.r('cess', '走（cedere）'),
      Morpheme.s('ive', '形容词后缀'),
    ],
    note: 'sub- + cedere「走」→ 接续而来的：连续的',
  ),
  'suicide': RootAnalysis(
    parts: [Morpheme.r('sui', '自己（sui）'), Morpheme.r('cid', '杀（caedere）'), Morpheme.s('e', '')],
    note: 'sui「自己」+ caedere「杀」→ 自杀',
  ),
  'suitcase': RootAnalysis(
    parts: [Morpheme.r('suit', '一套衣物'), Morpheme.r('case', '箱子')],
    note: 'suit「套装」+ case「箱」→ 装衣服的箱子：行李箱',
  ),
  'summit': RootAnalysis(
    parts: [Morpheme.r('summ', '最高（summus）'), Morpheme.s('it', '名词后缀')],
    note: 'summus「最高的」→ 山顶、峰会',
  ),
  'supervise': RootAnalysis(
    parts: [Morpheme.p('super', '在上'), Morpheme.r('vis', '看（videre）')],
    note: 'super- + videre「看」→ 从上面看：监督',
  ),
  'surge': RootAnalysis(
    parts: [Morpheme.r('surg', '升起（surgere）'), Morpheme.s('e', '')],
    note: 'surgere「升起」→ 涌起：激增',
  ),
  'susceptible': RootAnalysis(
    parts: [
      Morpheme.p('sus', '下面（sub-）'),
      Morpheme.r('cept', '拿（capere）'),
      Morpheme.s('ible', '可…的'),
    ],
    note: 'sub- + capere「拿」→ 容易被拿下的：易受影响的',
  ),
  'suspend': RootAnalysis(
    parts: [Morpheme.p('sus', '下面（sub-）'), Morpheme.r('pend', '挂（pendere）')],
    note: 'sub- + pendere「挂」→ 挂在下面：悬、暂停',
  ),

  // ===== T =====
  'tactics': RootAnalysis(
    parts: [Morpheme.r('tact', '接触、安排（tangere）'), Morpheme.s('ics', '学科后缀')],
    note: '希腊 taktika「排兵」→ 战术、策略',
  ),
  'tenant': RootAnalysis(
    parts: [Morpheme.r('ten', '持有（tenere）'), Morpheme.s('ant', '人')],
    note: 'tenere「持有」→ 持有租约的人：房客',
  ),
  'tentative': RootAnalysis(
    parts: [Morpheme.r('tent', '试（temptare）'), Morpheme.s('ative', '形容词后缀')],
    note: 'temptare「试」→ 试试看的：暂定的',
  ),
  'terminal': RootAnalysis(
    parts: [Morpheme.r('termin', '界限（terminus）'), Morpheme.s('al', '形容词后缀')],
    note: 'terminus「终点」→ 终点的、末端的：终端',
  ),
  'terminate': RootAnalysis(
    parts: [Morpheme.r('termin', '界限（terminus）'), Morpheme.s('ate', '动词后缀')],
    note: 'terminus「终点」→ 走到终点：终止',
  ),
  'terrace': RootAnalysis(
    parts: [Morpheme.r('terr', '土地（terra）'), Morpheme.s('ace', '名词后缀')],
    note: 'terra「土地」→ 整理出来的台地：露台、梯田',
  ),
  'territory': RootAnalysis(
    parts: [Morpheme.r('terr', '土地（terra）'), Morpheme.s('itory', '地方')],
    note: 'terra「土地」→ 一片地：领土',
  ),
  'thermometer': RootAnalysis(
    parts: [Morpheme.r('thermo', '热（thermē）'), Morpheme.r('meter', '测量（metron）')],
    note: 'thermē「热」+ metron「量」→ 温度计',
  ),
  'thrust': RootAnalysis(
    parts: [Morpheme.r('thrus', '推（古诺斯 þrysta）'), Morpheme.s('t', '')],
    note: '古诺斯语 þrysta「推」→ 猛推、推力',
  ),
  'transact': RootAnalysis(
    parts: [Morpheme.p('trans', '穿过、交换'), Morpheme.r('act', '做（agere）')],
    note: 'trans- + agere「做」→ 把事情做完并交出去：交易',
  ),
  'transmit': RootAnalysis(
    parts: [Morpheme.p('trans', '横过、转移'), Morpheme.r('mit', '送（mittere）')],
    note: 'trans- + mittere「送」→ 送到对面：传播、传送',
  ),
  'transparent': RootAnalysis(
    parts: [
      Morpheme.p('trans', '穿过'),
      Morpheme.r('par', '出现（parere）'),
      Morpheme.s('ent', '形容词后缀'),
    ],
    note: 'trans- + parere「显现」→ 光能穿过去看见：透明的',
  ),
  'treaty': RootAnalysis(
    parts: [Morpheme.r('treat', '处理、谈（tractare）'), Morpheme.s('y', '名词后缀')],
    note: 'tractare「谈」→ 谈成的东西：条约',
  ),
  'tremendous': RootAnalysis(
    parts: [Morpheme.r('tremend', '令人发抖（tremere）'), Morpheme.s('ous', '形容词后缀')],
    note: 'tremere「发抖」→ 大到让人发抖：巨大的',
  ),
  'tribe': RootAnalysis(
    parts: [Morpheme.r('trib', '划分（tribus）'), Morpheme.s('e', '')],
    note: '拉丁 tribus 原是罗马的三个部族 → 部落',
  ),
  'tribute': RootAnalysis(
    parts: [Morpheme.r('tribut', '给予（tribuere）'), Morpheme.s('e', '')],
    note: 'tribuere「给予」→ 献上去的东西：贡品、致敬',
  ),
  'triumphant': RootAnalysis(
    parts: [Morpheme.r('triumph', '凯旋（triumphus）'), Morpheme.s('ant', '形容词后缀')],
    note: 'triumphus「凯旋式」→ 得意洋洋的',
  ),
  'trumpet': RootAnalysis(
    parts: [Morpheme.r('trump', '喇叭（trumpa）'), Morpheme.s('et', '小')],
    note: 'trumpa「喇叭」+ -et「小」→ 小号',
  ),

  // ===== U =====
  'unveil': RootAnalysis(
    parts: [Morpheme.p('un', '打开、去掉'), Morpheme.r('veil', '面纱（velum）')],
    note: 'un- + velum「面纱」→ 揭掉面纱：揭幕、公布',
  ),
  'utilize': RootAnalysis(
    parts: [Morpheme.r('util', '有用（utilis）'), Morpheme.s('ize', '使…')],
    note: 'utilis「有用的」→ 使发挥作用：利用',
  ),
  'utile': RootAnalysis(
    parts: [Morpheme.r('util', '有用（utilis）'), Morpheme.s('e', '')],
    note: 'utilis「有用的」→ 有用的（现在少用）',
  ),
  'utility': RootAnalysis(
    parts: [Morpheme.r('util', '有用（utilis）'), Morpheme.s('ity', '名词后缀')],
    note: 'utilis「有用的」→ 效用、公用事业',
  ),

  // ===== V =====
  'vacant': RootAnalysis(
    parts: [Morpheme.r('vac', '空（vacare）'), Morpheme.s('ant', '形容词后缀')],
    note: 'vacare「空着」→ 空的：空缺的',
  ),
  'vacuum': RootAnalysis(
    parts: [Morpheme.r('vacu', '空（vacuus）'), Morpheme.s('um', '名词后缀')],
    note: 'vacuus「空的」→ 真空',
  ),
  'vague': RootAnalysis(
    parts: [Morpheme.r('vag', '游荡（vagus）'), Morpheme.s('ue', '')],
    note: 'vagus「游荡不定的」→ 模糊的',
  ),
  'validate': RootAnalysis(
    parts: [Morpheme.r('valid', '强、有效（validus）'), Morpheme.s('ate', '动词后缀')],
    note: 'validus「强壮的」→ 使站得住：验证',
  ),
  'validation': RootAnalysis(
    parts: [
      Morpheme.r('valid', '强、有效（validus）'),
      Morpheme.s('ation', '名词后缀'),
    ],
    note: '同 validate：验证',
  ),
  'vanish': RootAnalysis(
    parts: [Morpheme.r('van', '空（vanus）'), Morpheme.s('ish', '动词后缀')],
    note: 'vanus「空的」→ 变空：消失',
  ),
  'venture': RootAnalysis(
    parts: [Morpheme.r('vent', '来（venire）'), Morpheme.s('ure', '名词后缀')],
    note: 'venire「来」→ 不知道会来什么就去做：冒险、企业',
  ),
  'verbal': RootAnalysis(
    parts: [Morpheme.r('verb', '词（verbum）'), Morpheme.s('al', '形容词后缀')],
    note: 'verbum「词」→ 言辞的、口头的',
  ),
  'verify': RootAnalysis(
    parts: [Morpheme.r('ver', '真实（verus）'), Morpheme.s('ify', '使…')],
    note: 'verus「真」→ 使成真、查实：核实',
  ),
  'versatile': RootAnalysis(
    parts: [Morpheme.r('vers', '转（vertere）'), Morpheme.s('atile', '形容词后缀')],
    note: 'vertere「转」→ 能转得开的：多才多艺的、多用途的',
  ),
  'versus': RootAnalysis(
    parts: [Morpheme.r('vers', '转（vertere）'), Morpheme.s('us', '后缀')],
    note: 'vertere「转」→ 转向对方：对、与…相对',
  ),
  'via': RootAnalysis(
    parts: [Morpheme.r('via', '路（拉丁 via）'), Morpheme.s('', '')],
    note: '拉丁 via 就是「道路」→ 经由',
  ),
  'vibrant': RootAnalysis(
    parts: [Morpheme.r('vibr', '振动（vibrare）'), Morpheme.s('ant', '形容词后缀')],
    note: 'vibrare「振动」→ 带震动的：充满活力的',
  ),
  'violate': RootAnalysis(
    parts: [Morpheme.r('viol', '暴力（vis「力量」）'), Morpheme.s('ate', '动词后缀')],
    note: 'vis「力量」→ 用强：违反、侵犯',
  ),
  'vigorous': RootAnalysis(
    parts: [Morpheme.r('vigor', '活力（vigere）'), Morpheme.s('ous', '形容词后缀')],
    note: 'vigere「旺盛」→ 精力充沛的',
  ),
  'vulnerable': RootAnalysis(
    parts: [Morpheme.r('vulner', '伤（vulnus）'), Morpheme.s('able', '可…的')],
    note: 'vulnus「伤口」→ 容易受伤的：脆弱的',
  ),

  // ===== W =====
  'withdrawal': RootAnalysis(
    parts: [Morpheme.p('with', '向后'), Morpheme.r('draw', '拉'), Morpheme.s('al', '名词后缀')],
    note: 'with-「回」+ draw「拉」→ 往回拉：撤回、取款',
  ),

  // ===== X / Y / Z =====
};
