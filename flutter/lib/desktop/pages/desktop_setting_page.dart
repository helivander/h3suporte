import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/common/widgets/keyboard_shortcuts/page_body.dart';
import 'package:flutter_hbb/desktop/pages/desktop_keyboard_shortcuts_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/printer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/shortcut_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common/widgets/dialog.dart';
import '../../common/widgets/login.dart';
import 'h3_conta_painel.dart';
import 'h3_ia_config.dart';
import 'h3_home_layout.dart';

const double _kTabWidth = 220;
const double _kTabHeight = 42;
const double _kCardFixedWidth = 680;
const double _kCardLeftMargin = 15;
const double _kContentHMargin = 15;
const double _kContentHSubMargin = _kContentHMargin + 33;
const double _kCheckBoxLeftMargin = 10;
const double _kRadioLeftMargin = 10;
const double _kListViewBottomMargin = 15;
const double _kTitleFontSize = 20;
const double _kContentFontSize = 15;
const Color _accentColor = MyTheme.accent;
const String _kSettingPageControllerTag = 'settingPageController';
const String _kSettingPageTabKeyTag = 'settingPageTabKey';

class _TabInfo {
  late final SettingsTabKey key;
  late final String label;
  late final IconData unselected;
  late final IconData selected;
  _TabInfo(this.key, this.label, this.unselected, this.selected);
}

enum SettingsTabKey {
  general,
  safety,
  network,
  display,
  account,
  printer,
  ia,
  about,
}

class DesktopSettingPage extends StatefulWidget {
  final SettingsTabKey initialTabkey;
  static final List<SettingsTabKey> tabKeys = [
    if (bind.mainGetBuildinOption(key: kOptionHideGeneralSetting) != 'Y')
      SettingsTabKey.general,
    if (!isWeb &&
        !bind.isOutgoingOnly() &&
        !bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      SettingsTabKey.safety,
    if (!bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) != 'Y')
      SettingsTabKey.network,
    if (!bind.isIncomingOnly()) SettingsTabKey.display,
    if (!bind.isDisableAccount()) SettingsTabKey.account,
    if (isWindows &&
        !bind.isDisableSettings() &&
        bind.mainGetBuildinOption(key: kOptionHideRemotePrinterSetting) != 'Y')
      SettingsTabKey.printer,
    if (kH3IaBuild) SettingsTabKey.ia,
    SettingsTabKey.about,
  ];

  DesktopSettingPage({Key? key, required this.initialTabkey}) : super(key: key);

  @override
  State<DesktopSettingPage> createState() =>
      _DesktopSettingPageState(initialTabkey);

  static void switch2page(SettingsTabKey page) {
    try {
      int index = tabKeys.indexOf(page);
      if (index == -1) {
        return;
      }
      if (Get.isRegistered<PageController>(tag: _kSettingPageControllerTag) &&
          Get.isRegistered<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag)) {
        DesktopTabPage.onAddSetting(initialPage: page);
        PageController controller =
            Get.find<PageController>(tag: _kSettingPageControllerTag);
        Rx<SettingsTabKey> selected =
            Get.find<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
        selected.value = page;
        controller.jumpToPage(index);
      } else {
        DesktopTabPage.onAddSetting(initialPage: page);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopSettingPageState extends State<DesktopSettingPage>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late PageController controller;
  late Rx<SettingsTabKey> selectedTab;

  @override
  bool get wantKeepAlive => true;

  final RxBool _block = false.obs;
  final RxBool _canBeBlocked = false.obs;
  Timer? _videoConnTimer;

  _DesktopSettingPageState(SettingsTabKey initialTabkey) {
    var initialIndex = DesktopSettingPage.tabKeys.indexOf(initialTabkey);
    if (initialIndex == -1) {
      initialIndex = 0;
    }
    selectedTab = DesktopSettingPage.tabKeys[initialIndex].obs;
    h3ConfigAbaAtual.value = selectedTab.value;
    ever(selectedTab, (v) => h3ConfigAbaAtual.value = v);
    Get.put<Rx<SettingsTabKey>>(selectedTab, tag: _kSettingPageTabKeyTag);
    controller = PageController(initialPage: initialIndex);
    Get.put<PageController>(controller, tag: _kSettingPageControllerTag);
    controller.addListener(() {
      if (controller.page != null) {
        int page = controller.page!.toInt();
        if (page < DesktopSettingPage.tabKeys.length) {
          selectedTab.value = DesktopSettingPage.tabKeys[page];
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _videoConnTimer =
        periodic_immediate(Duration(milliseconds: 1000), () async {
      if (!mounted) {
        return;
      }
      final blocked = await canBeBlocked();
      if (!mounted) {
        return;
      }
      _canBeBlocked.value = blocked;
    });
  }

  @override
  void dispose() {
    _videoConnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    Get.delete<PageController>(tag: _kSettingPageControllerTag);
    Get.delete<Rx<SettingsTabKey>>(tag: _kSettingPageTabKeyTag);
    // Get.delete does not dispose a plain ChangeNotifier.
    controller.dispose();
    super.dispose();
  }

  List<_TabInfo> _settingTabs() {
    final List<_TabInfo> settingTabs = <_TabInfo>[];
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          settingTabs.add(_TabInfo(
              tab, 'General', Icons.settings_outlined, Icons.settings));
          break;
        case SettingsTabKey.safety:
          settingTabs.add(_TabInfo(tab, 'Security',
              Icons.enhanced_encryption_outlined, Icons.enhanced_encryption));
          break;
        case SettingsTabKey.network:
          settingTabs
              .add(_TabInfo(tab, 'Network', Icons.link_outlined, Icons.link));
          break;
        case SettingsTabKey.display:
          settingTabs.add(_TabInfo(tab, 'Display',
              Icons.desktop_windows_outlined, Icons.desktop_windows));
          break;
        case SettingsTabKey.account:
          settingTabs.add(
              _TabInfo(tab, 'Account', Icons.person_outline, Icons.person));
          break;
        case SettingsTabKey.printer:
          settingTabs
              .add(_TabInfo(tab, 'Printer', Icons.print_outlined, Icons.print));
          break;
        case SettingsTabKey.ia:
          settingTabs.add(_TabInfo(
              tab, 'IA', Icons.smart_toy_outlined, Icons.smart_toy));
          break;
        case SettingsTabKey.about:
          settingTabs
              .add(_TabInfo(tab, 'About', Icons.info_outline, Icons.info));
          break;
      }
    }
    return settingTabs;
  }

  Widget _estreita(Widget w) => bind.isIncomingOnly()
      ? w
      : Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: double.infinity), child: w));

  List<Widget> _children() {
    final children = List<Widget>.empty(growable: true);
    for (final tab in DesktopSettingPage.tabKeys) {
      switch (tab) {
        case SettingsTabKey.general:
          children.add(const _General());
          break;
        case SettingsTabKey.safety:
          children.add(const _Safety());
          break;
        case SettingsTabKey.network:
          children.add(_estreita(const _Network()));
          break;
        case SettingsTabKey.display:
          children.add(const _Display());
          break;
        case SettingsTabKey.account:
          children.add(_estreita(const _Account()));
          break;
        case SettingsTabKey.printer:
          children.add(_estreita(const _Printer()));
          break;
        case SettingsTabKey.ia:
          children.add(_estreita(const IaConfig()));
          break;
        case SettingsTabKey.about:
          children.add(_estreita(const _About()));
          break;
      }
    }
    return children;
  }

  Widget _buildBlock({required List<Widget> children}) {
    // check both mouseMoveTime and videoConnCount
    return Obx(() {
      final videoConnBlock =
          _canBeBlocked.value && stateGlobal.videoConnCount > 0;
      return Stack(children: [
        buildRemoteBlock(
          block: _block,
          mask: false,
          use: canBeBlocked,
          child: preventMouseKeyBuilder(
            child: Row(children: children),
            block: videoConnBlock,
          ),
        ),
        if (videoConnBlock)
          Container(
            color: Colors.black.withOpacity(0.5),
          )
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (bind.isIncomingOnly()) return _corpo(context);
    final tema = H3Cores.tema(Theme.of(context).brightness);
    return Theme(
        key: ValueKey(H3Cores.escuro),
        data: tema,
        child: Builder(builder: (ctx) => _corpo(ctx)));
  }

  Widget _corpo(BuildContext context) {
    final h3 = !bind.isIncomingOnly();
    final menu = Container(
      width: _kTabWidth,
      decoration: h3
          ? BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [H3Cores.painel2, H3Cores.painel]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: H3Cores.linha))
          : null,
      child: Column(
        children: [
          _header(context),
          Flexible(child: _listView(tabs: _settingTabs())),
        ],
      ),
    );
    final pagina = PageView(
      controller: controller,
      physics: NeverScrollableScrollPhysics(),
      children: _children(),
    );
    return Scaffold(
      backgroundColor:
          h3 ? H3Cores.fundo : Theme.of(context).colorScheme.background,
      body: _buildBlock(
        children: <Widget>[
          if (h3) Padding(padding: const EdgeInsets.all(14), child: menu) else menu,
          if (!h3)
            VerticalDivider(width: 1),
          Expanded(
            child: Container(
              color: h3 ? null : Theme.of(context).scaffoldBackgroundColor,
              padding: h3 ? const EdgeInsets.fromLTRB(0, 14, 14, 14) : null,
              child: Align(
                alignment: h3 ? Alignment.topLeft : Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: double.infinity),
                  child: pagina,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final settingsText = Text(
      translate('Settings'),
      textAlign: TextAlign.left,
      style: TextStyle(
        color: bind.isIncomingOnly() ? _accentColor : H3Cores.texto,
        fontSize: bind.isIncomingOnly() ? _kTitleFontSize : 18,
        fontWeight:
            bind.isIncomingOnly() ? FontWeight.w400 : FontWeight.w600,
      ),
    );
    return Row(
      children: [
        if (isWeb)
          IconButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            icon: Icon(Icons.arrow_back),
          ).marginOnly(left: 5),
        if (isWeb)
          SizedBox(
            height: 62,
            child: Align(
              alignment: Alignment.center,
              child: settingsText,
            ),
          ).marginOnly(left: 20),
        if (!isWeb)
          SizedBox(
            height: 62,
            child: settingsText,
          ).marginOnly(left: 20, top: 10),
        const Spacer(),
      ],
    );
  }

  Widget _listView({required List<_TabInfo> tabs}) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: tabs.map((tab) => _listItem(tab: tab)).toList(),
    );
  }

  Widget _itemH3(_TabInfo tab, bool selected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          final index = DesktopSettingPage.tabKeys.indexOf(tab.key);
          if (index == -1) return;
          if (selectedTab.value != tab.key) controller.jumpToPage(index);
          selectedTab.value = tab.key;
        },
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: selected
                ? LinearGradient(colors: [
                    H3Cores.destaque.withOpacity(0.22),
                    H3Cores.destaque.withOpacity(0.06),
                  ])
                : null,
          ),
          child: Row(children: [
            Icon(selected ? tab.selected : tab.unselected,
                size: 20,
                color: selected ? H3Cores.destaque : H3Cores.apagado),
            const SizedBox(width: 12),
            Expanded(
              child: Text(translate(tab.label),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? H3Cores.texto : H3Cores.apagado)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _listItem({required _TabInfo tab}) {
    return Obx(() {
      bool selected = tab.key == selectedTab.value;
      if (!bind.isIncomingOnly()) return _itemH3(tab, selected);
      return SizedBox(
        width: _kTabWidth,
        height: _kTabHeight,
        child: InkWell(
          onTap: () {
            if (selectedTab.value != tab.key) {
              int index = DesktopSettingPage.tabKeys.indexOf(tab.key);
              if (index == -1) {
                return;
              }
              controller.jumpToPage(index);
            }
            selectedTab.value = tab.key;
          },
          child: Row(children: [
            Container(
              width: 4,
              height: _kTabHeight * 0.7,
              color: selected ? _accentColor : null,
            ),
            Icon(
              selected ? tab.selected : tab.unselected,
              color: selected ? _accentColor : null,
              size: 20,
            ).marginOnly(left: 13, right: 10),
            Text(
              translate(tab.label),
              style: TextStyle(
                  color: selected ? _accentColor : null,
                  fontWeight: FontWeight.w400,
                  fontSize: _kContentFontSize),
            ),
          ]),
        ),
      );
    });
  }
}

//#region pages

class _General extends StatefulWidget {
  const _General({Key? key}) : super(key: key);

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> {
  final RxBool serviceStop =
      isWeb ? RxBool(false) : Get.find<RxBool>(tag: 'stop-service');
  RxBool serviceBtnEnabled = true.obs;
  final GlobalKey _minToolbarOptionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return _duasColunas(scrollController, [
        if (!isWeb) service(),
        theme(),
        _Card(title: 'Language', children: [language()]),
        if (!isWeb) hwcodec(),
        if (!isWeb) audio(context),
        if (!isWeb) record(context),
        if (!isWeb) WaylandCard(),
        other(),
        if (!bind.isIncomingOnly()) keyboardShortcuts(),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget keyboardShortcuts() {
    // The bindings JSON (LocalConfig key `keyboard-shortcuts`) holds three
    // flags + the bindings list: {enabled, pass_through, bindings}. When the
    // master is off, the pass-through toggle and the Configure entry are
    // hidden — both are meaningless without an active matcher.
    return StatefulBuilder(builder: (context, setLocalState) {
      final enabled = ShortcutModel.isEnabled();
      return _Card(title: 'Keyboard shortcuts', children: [
        _OptionCheckBox(
          context,
          'Enable keyboard shortcuts in remote session',
          kShortcutLocalConfigKey,
          isServer: false,
          optGetter: ShortcutModel.isEnabled,
          optSetter: (_, v) async {
            await ShortcutModel.setEnabled(v);
            setLocalState(() {});
          },
        ),
        if (enabled) ...[
          _OptionCheckBox(
            context,
            'Pass-through to remote',
            kShortcutLocalConfigKey,
            isServer: false,
            optGetter: ShortcutModel.isPassThrough,
            optSetter: (_, v) async {
              await ShortcutModel.setPassThrough(v);
              setLocalState(() {});
            },
            trailing: const InfoTooltipIcon(tipKey: 'shortcut-passthrough-tip'),
          ),
          _ShortcutsConfigureRow(),
        ],
      ]);
    });
  }

  Widget theme() {
    final current = MyTheme.getThemeModePreference().toShortString();
    onChanged(String value) async {
      await MyTheme.changeDarkMode(MyTheme.themeModeFromString(value));
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kCommConfKeyTheme);
    return _Card(title: 'Theme', children: [
      _Radio<String>(context,
          value: 'light',
          groupValue: current,
          label: 'Light',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'dark',
          groupValue: current,
          label: 'Dark',
          onChanged: isOptFixed ? null : onChanged),
      _Radio<String>(context,
          value: 'system',
          groupValue: current,
          label: 'Follow System',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget service() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    final hideStopService =
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';

    return Obx(() {
      if (hideStopService && !serviceStop.value) {
        return const Offstage();
      }

      return _Card(title: 'Service', children: [
        _Button(serviceStop.value ? 'Start' : 'Stop', () {
          () async {
            serviceBtnEnabled.value = false;
            await start_service(serviceStop.value);
            // enable the button after 1 second
            Future.delayed(const Duration(seconds: 1), () {
              serviceBtnEnabled.value = true;
            });
          }();
        }, enabled: serviceBtnEnabled.value)
      ]);
    });
  }

  Widget other() {
    final incomingOnly = bind.isIncomingOnly();
    final outgoingOnly = bind.isOutgoingOnly();
    final showAutoUpdate = (isWindows && bind.mainIsInstalled()) ||
    (isMacOS && bind.mainIsInstalled() && bind.mainIsInstalledDaemon(prompt: false));
    final children = <Widget>[
      if (!isWeb && !incomingOnly)
        _OptionCheckBox(context, 'Confirm before closing multiple tabs',
            kOptionEnableConfirmClosingTabs,
            isServer: false),
      if (!incomingOnly)
        _OptionCheckBox(
          context,
          'allow-remote-toolbar-docking-any-edge',
          kOptionAllowMultiEdgeToolbarDock,
          isServer: false,
          update: (_) {
            reloadAllWindows();
          },
        ),
      if (!isWeb && !outgoingOnly)
        _OptionCheckBox(context, 'Adaptive bitrate', kOptionEnableAbr),
      if (!isWeb) wallpaper(),
      if (!isWeb && !incomingOnly) ...[
        _OptionCheckBox(
          context,
          'Open connection in new tab',
          kOptionOpenNewConnInTabs,
          isServer: false,
        ),
        Tooltip(
          message: translate('port-forward-mux-tip'),
          child: _OptionCheckBox(
            context,
            'Reuse one connection for port forwarding',
            kOptionEnablePortForwardMux,
            isServer: false,
          ),
        ),
        // though this is related to GUI, but opengl problem affects all users, so put in config rather than local
        if (isLinux)
          Tooltip(
            message: translate('software_render_tip'),
            child: _OptionCheckBox(
              context,
              "Always use software rendering",
              kOptionAllowAlwaysSoftwareRender,
            ),
          ),
        if (!isWeb)
          Tooltip(
            message: translate('texture_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use texture rendering",
              kOptionTextureRender,
              optGetter: bind.mainGetUseTextureRender,
              optSetter: (k, v) async =>
                  await bind.mainSetLocalOption(key: k, value: v ? 'Y' : 'N'),
            ),
          ),
        if (isWindows)
          Tooltip(
            message: translate('d3d_render_tip'),
            child: _OptionCheckBox(
              context,
              "Use D3D rendering",
              kOptionD3DRender,
              isServer: false,
            ),
          ),
      ],
      if (!isWeb)
        _OptionCheckBox(
          context,
          'Check for software update on startup',
          kOptionEnableCheckUpdate,
          isServer: false,
        ),
      if (showAutoUpdate)
        _OptionCheckBox(
          context,
          'Auto update',
          kOptionAllowAutoUpdate,
          isServer: true,
        ),
      if (isWindows && !outgoingOnly)
        _OptionCheckBox(
          context,
          'Capture screen using DirectX',
          kOptionDirectxCapture,
        ),
      if (!isWeb && !incomingOnly) ...[
        _OptionCheckBox(
          context,
          'Enable TCP hole punching',
          kOptionEnableTcpPunch,
          isServer: false,
        ),
        _OptionCheckBox(
          context,
          'Enable UDP hole punching',
          kOptionEnableUdpPunch,
          isServer: false,
        ),
        _OptionCheckBox(
          context,
          'Enable IPv6 P2P connection',
          kOptionEnableIpv6Punch,
          isServer: false,
        ),
      ],
      if (!incomingOnly) ...webrtcOptions(context),
      if (!isWeb && !incomingOnly)
        Tooltip(
          message: translate('sync-clipboard-between-sessions-tip'),
          child: _OptionCheckBox(
            context,
            'Sync clipboard between sessions',
            kOptionAllowSyncClipboardBetweenSessions,
            isServer: false,
          ),
        ),
    ];

    // Add client-side wakelock option for desktop platforms
    if (!bind.isIncomingOnly()) {
      children.add(_OptionCheckBox(
        context,
        'keep-awake-during-outgoing-sessions-label',
        kOptionKeepAwakeDuringOutgoingSessions,
        isServer: false,
      ));
    }

    if (!bind.isDisableAccount()) {
      children.add(_OptionCheckBox(
        context,
        'note-at-conn-end-tip',
        kOptionAllowAskForNoteAtEndOfConnection,
        isServer: false,
        optSetter: (key, value) async {
          if (value && !gFFI.userModel.isLogin) {
            final res = await loginDialog();
            if (res != true) return;
          }
          await mainSetLocalBoolOption(key, value);
        },
      ));
    }
    children.add(_OptionCheckBox(
      context,
      'Show monitor switch button on the main toolbar',
      kOptionAllowMonitorSwitchMainToolbar,
      isServer: false,
      update: (enabled) async {
        if (!enabled) {
          await mainSetLocalBoolOption(
              kOptionAllowMonitorSwitchMinToolbar, false);
        }
        if (mounted) setState(() {});
        reloadAllWindows();
        if (enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _minToolbarOptionKey.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                alignment: 0.5,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            }
          });
        }
      },
    ));
    if (mainGetLocalBoolOptionSync(kOptionAllowMonitorSwitchMainToolbar)) {
      children.add(KeyedSubtree(
        key: _minToolbarOptionKey,
        child: _OptionCheckBox(
          context,
          'Show on the minimized toolbar',
          kOptionAllowMonitorSwitchMinToolbar,
          isServer: false,
          update: (_) {
            reloadAllWindows();
          },
        ).marginOnly(left: _kCheckBoxLeftMargin * 3),
      ));
    }
    return _Card(title: 'Other', children: children);
  }

  Widget wallpaper() {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    return futureBuilder(future: () async {
      final support = await bind.mainSupportRemoveWallpaper();
      return support;
    }(), hasData: (data) {
      if (data is bool && data == true) {
        bool value = mainGetBoolOptionSync(kOptionAllowRemoveWallpaper);
        return Row(
          children: [
            Flexible(
              child: _OptionCheckBox(
                context,
                'Remove wallpaper during incoming sessions',
                kOptionAllowRemoveWallpaper,
                update: (bool v) {
                  setState(() {});
                },
              ),
            ),
            if (value)
              _CountDownButton(
                text: 'Test',
                second: 5,
                onPressed: () {
                  bind.mainTestWallpaper(second: 5);
                },
              )
          ],
        );
      }

      return Offstage();
    });
  }

  Widget hwcodec() {
    final hwcodec = bind.mainHasHwcodec();
    final vram = bind.mainHasVram();
    return Offstage(
      offstage: !(hwcodec || vram),
      child: _Card(title: 'Hardware Codec', children: [
        _OptionCheckBox(
          context,
          'Enable hardware codec',
          kOptionEnableHwcodec,
          update: (bool v) {
            if (v) {
              bind.mainCheckHwcodec();
            }
          },
        )
      ]),
    );
  }

  Widget audio(BuildContext context) {
    if (bind.isOutgoingOnly()) {
      return const Offstage();
    }

    builder(devices, currentDevice, setDevice) {
      final child = ComboBox(
        keys: devices,
        values: devices,
        initialKey: currentDevice,
        onChanged: (key) async {
          setDevice(key);
          setState(() {});
        },
      ).marginOnly(left: _kContentHMargin);
      return _Card(title: 'Audio Input Device', children: [child]);
    }

    return AudioInput(builder: builder, isCm: false, isVoiceCall: false);
  }

  Widget record(BuildContext context) {
    final showRootDir = isWindows && bind.mainIsInstalled();
    return futureBuilder(future: () async {
      String user_dir = bind.mainVideoSaveDirectory(root: false);
      String root_dir =
          showRootDir ? bind.mainVideoSaveDirectory(root: true) : '';
      bool user_dir_exists = await Directory(user_dir).exists();
      bool root_dir_exists =
          showRootDir ? await Directory(root_dir).exists() : false;
      return {
        'user_dir': user_dir,
        'root_dir': root_dir,
        'user_dir_exists': user_dir_exists,
        'root_dir_exists': root_dir_exists,
      };
    }(), hasData: (data) {
      Map<String, dynamic> map = data as Map<String, dynamic>;
      String user_dir = map['user_dir']!;
      String root_dir = map['root_dir']!;
      bool root_dir_exists = map['root_dir_exists']!;
      bool user_dir_exists = map['user_dir_exists']!;
      return _Card(title: 'Recording', children: [
        if (!bind.isOutgoingOnly())
          _OptionCheckBox(context, 'Automatically record incoming sessions',
              kOptionAllowAutoRecordIncoming),
        if (!bind.isIncomingOnly())
          _OptionCheckBox(context, 'Automatically record outgoing sessions',
              kOptionAllowAutoRecordOutgoing,
              isServer: false),
        if (showRootDir && !bind.isOutgoingOnly())
          Row(
            children: [
              Text(
                  '${translate(bind.isIncomingOnly() ? "Directory" : "Incoming")}:'),
              Expanded(
                child: GestureDetector(
                    onTap: root_dir_exists
                        ? () => launchUrl(Uri.file(root_dir))
                        : null,
                    child: Text(
                      root_dir,
                      softWrap: true,
                      style: root_dir_exists
                          ? const TextStyle(
                              decoration: TextDecoration.underline)
                          : null,
                    )).marginOnly(left: 10),
              ),
            ],
          ).marginOnly(left: _kContentHMargin),
        if (!(showRootDir && bind.isIncomingOnly()))
          Row(
            children: [
              Text(
                  '${translate((showRootDir && !bind.isOutgoingOnly()) ? "Outgoing" : "Directory")}:'),
              Expanded(
                child: GestureDetector(
                    onTap: user_dir_exists
                        ? () => launchUrl(Uri.file(user_dir))
                        : null,
                    child: Text(
                      user_dir,
                      softWrap: true,
                      style: user_dir_exists
                          ? const TextStyle(
                              decoration: TextDecoration.underline)
                          : null,
                    )).marginOnly(left: 10),
              ),
              ElevatedButton(
                      onPressed: isOptionFixed(kOptionVideoSaveDirectory)
                          ? null
                          : () async {
                              String? initialDirectory;
                              if (await Directory.fromUri(
                                      Uri.directory(user_dir))
                                  .exists()) {
                                initialDirectory = user_dir;
                              }
                              String? selectedDirectory =
                                  await FilePicker.platform.getDirectoryPath(
                                      initialDirectory: initialDirectory);
                              if (selectedDirectory != null) {
                                await bind.mainSetLocalOption(
                                    key: kOptionVideoSaveDirectory,
                                    value: selectedDirectory);
                                setState(() {});
                              }
                            },
                      child: Text(translate('Change')))
                  .marginOnly(left: 5),
            ],
          ).marginOnly(left: _kContentHMargin),
      ]);
    });
  }

  Widget language() {
    return futureBuilder(future: () async {
      String langs = await bind.mainGetLangs();
      return {'langs': langs};
    }(), hasData: (res) {
      Map<String, String> data = res as Map<String, String>;
      List<dynamic> langsList = jsonDecode(data['langs']!);
      Map<String, String> langsMap = {for (var v in langsList) v[0]: v[1]};
      List<String> keys = langsMap.keys.toList();
      List<String> values = langsMap.values.toList();
      keys.insert(0, defaultOptionLang);
      values.insert(0, translate('Default'));
      String currentKey = bind.mainGetLocalOption(key: kCommConfKeyLang);
      if (!keys.contains(currentKey)) {
        currentKey = defaultOptionLang;
      }
      final isOptFixed = isOptionFixed(kCommConfKeyLang);
      return ComboBox(
        keys: keys,
        values: values,
        initialKey: currentKey,
        onChanged: (key) async {
          await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
          if (isWeb) reloadCurrentWindow();
          if (!isWeb) reloadAllWindows();
          if (!isWeb) bind.mainChangeLanguage(lang: key);
        },
        enabled: !isOptFixed,
      ).marginOnly(left: _kContentHMargin);
    });
  }

  // How long an already-connected relay is held back to give the direct WebRTC
  // attempt a chance to win. It only means anything while WebRTC is on, so it
  // follows the checkbox as an indented sub-option and is hidden outright when
  // the box is clear — the shape `directIp` uses for its port.
  List<Widget> webrtcOptions(BuildContext context) {
    final stored = bind.mainGetLocalOption(key: kOptionRelayFallbackDelay);
    final controller = TextEditingController(text: stored);
    // What the field holds against what is saved. Apply is offered only while
    // the two differ, so an untouched field shows no button at all, and neither
    // does one typed back to its saved value or cleared when nothing was saved
    // — the state an "edited" flag alone would still call dirty.
    final typed = RxString(stored);
    final saved = RxString(stored);
    return [
      _OptionCheckBox(
        context,
        'Enable WebRTC P2P connection',
        kOptionEnableWebrtc,
        isServer: false,
        update: (_) => setState(() {}),
      ),
      () {
        final enabled = mainGetLocalBoolOptionSync(kOptionEnableWebrtc);
        final isOptFixed = isOptionFixed(kOptionRelayFallbackDelay);
        return Offstage(
          offstage: !enabled,
          child: Tooltip(
            message: translate('relay-fallback-delay-tip'),
            child: _SubLabeledWidget(
              context,
              'Relay fallback delay in seconds',
              Row(children: [
                SizedBox(
                  width: 95,
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !isOptFixed,
                    onChanged: (v) => typed.value = v,
                    inputFormatters: [
                      // Seconds, at most one decimal. Clearing the field is
                      // allowed and restores the built-in default.
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^([0-9]|[1-9][0-9])(\.[0-9]?)?$')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '2.5',
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ).workaroundFreezeLinuxMint().marginOnly(right: 15),
                ),
                Obx(() => Offstage(
                      offstage: typed.value.trim() == saved.value.trim(),
                      child: ElevatedButton(
                        onPressed: enabled &&
                                !isOptFixed &&
                                !typed.value.trim().endsWith('.') &&
                                double.tryParse(typed.value.trim()) != 0
                            ? () async {
                                final v = controller.text.trim();
                                await bind.mainSetLocalOption(
                                    key: kOptionRelayFallbackDelay, value: v);
                                if (controller.text != v) controller.text = v;
                                typed.value = v;
                                saved.value = v;
                              }
                            : null,
                        child: Text(translate('Apply')),
                      ),
                    ))
              ]),
              enabled: enabled && !isOptFixed,
            ),
          ),
        );
      }(),
    ];
  }
}

enum _AccessMode {
  custom,
  full,
  view,
}

class _Safety extends StatefulWidget {
  const _Safety({Key? key}) : super(key: key);

  @override
  State<_Safety> createState() => _SafetyState();
}

class _SafetyState extends State<_Safety> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = bind.mainIsInstalled();
  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            _lock(locked, 'Unlock Security Settings', () {
              locked = false;
              setState(() => {});
            }),
            preventMouseKeyBuilder(
              block: locked,
              child: _colunasSimples([
                permissions(context),
                more(context),
                password(context),
                _Card(title: '2FA', children: [tfa()]),
                if (!isChangeIdDisabled())
                  _Card(title: 'ID', children: [changeId()]),
              ]),
            ),
          ],
        )).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget tfa() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool has2fa = bind.mainHasValid2FaSync().obs;
      RxBool hasBot = bind.mainHasValidBotSync().obs;
      update() async {
        has2fa.value = bind.mainHasValid2FaSync();
        setState(() {});
      }

      onChanged(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-2fa-confirm-tip'), () {
            change2fa(callback: update);
          });
        } else {
          change2fa(callback: update);
        }
      }

      final tfa = GestureDetector(
        child: InkWell(
          child: Obx(() => Row(
                children: [
                  Checkbox(
                          value: has2fa.value,
                          onChanged: enabled ? onChanged : null)
                      .marginOnly(right: 5),
                  Expanded(
                      child: Text(
                    translate('enable-2fa-title'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  ))
                ],
              )),
        ),
        onTap: () {
          onChanged(!has2fa.value);
        },
      ).marginOnly(left: _kCheckBoxLeftMargin);
      if (!has2fa.value) {
        return tfa;
      }
      updateBot() async {
        hasBot.value = bind.mainHasValidBotSync();
        setState(() {});
      }

      onChangedBot(bool? checked) async {
        if (checked == false) {
          CommonConfirmDialog(
              gFFI.dialogManager, translate('cancel-bot-confirm-tip'), () {
            changeBot(callback: updateBot);
          });
        } else {
          changeBot(callback: updateBot);
        }
      }

      final bot = GestureDetector(
        child: Tooltip(
          waitDuration: Duration(milliseconds: 300),
          message: translate("enable-bot-tip"),
          child: InkWell(
              child: Obx(() => Row(
                    children: [
                      Checkbox(
                              value: hasBot.value,
                              onChanged: enabled ? onChangedBot : null)
                          .marginOnly(right: 5),
                      Expanded(
                          child: Text(
                        translate('Telegram bot'),
                        style: TextStyle(
                            color: disabledTextColor(context, enabled)),
                      ))
                    ],
                  ))),
        ),
        onTap: () {
          onChangedBot(!hasBot.value);
        },
      ).marginOnly(left: _kCheckBoxLeftMargin + 30);

      final trust = Row(
        children: [
          Flexible(
            child: Tooltip(
              waitDuration: Duration(milliseconds: 300),
              message: translate("enable-trusted-devices-tip"),
              child: _OptionCheckBox(context, "Enable trusted devices",
                  kOptionEnableTrustedDevices,
                  optSetter: (key, value) async {
                try {
                  await mainSetBoolOption(key, value);
                } catch (error) {
                  showToast(error.toString());
                }
              },
                  enabled: !locked, update: (v) {
                setState(() {});
              }),
            ),
          ),
          if (mainGetBoolOptionSync(kOptionEnableTrustedDevices))
            ElevatedButton(
                onPressed: locked
                    ? null
                    : () {
                        manageTrustedDeviceDialog();
                      },
                child: Text(translate('Manage trusted devices')))
        ],
      ).marginOnly(left: 30);

      return Column(
        children: [
          tfa,
          bot,
          trust,
          if (mainGetBoolOptionSync(kOptionEnableTrustedDevices))
            trustedDeviceExpiration(
              enabled: !locked,
              onChanged: () {
                if (mounted) setState(() {});
              },
            ).marginOnly(
              left: _kCheckBoxLeftMargin + 20 + _kContentHSubMargin,
              top: _kContentHMargin,
            ),
        ],
      );
    }

    return tmpWrapper();
  }

  Widget changeId() {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          return _Button('Change ID', changeIdDialog,
              enabled: !locked && model.connectStatus > 0);
        })));
  }

  Widget permissions(context) {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      String accessMode = bind.mainGetOptionSync(key: kOptionAccessMode);
      _AccessMode mode;
      if (accessMode == 'full') {
        mode = _AccessMode.full;
      } else if (accessMode == 'view') {
        mode = _AccessMode.view;
      } else {
        mode = _AccessMode.custom;
      }
      String initialKey;
      bool? fakeValue;
      switch (mode) {
        case _AccessMode.custom:
          initialKey = '';
          fakeValue = null;
          break;
        case _AccessMode.full:
          initialKey = 'full';
          fakeValue = true;
          break;
        case _AccessMode.view:
          initialKey = 'view';
          fakeValue = false;
          break;
      }

      return _Card(title: 'Permissions', children: [
        ComboBox(
            keys: [
              defaultOptionAccessMode,
              'full',
              'view',
            ],
            values: [
              translate('Custom'),
              translate('Full Access'),
              translate('Screen Share'),
            ],
            enabled: enabled && !isOptionFixed(kOptionAccessMode),
            initialKey: initialKey,
            onChanged: (mode) async {
              await bind.mainSetOption(key: kOptionAccessMode, value: mode);
              setState(() {});
            }).marginOnly(left: _kContentHMargin),
        Column(
          children: [
            _OptionCheckBox(
                context, 'Enable keyboard/mouse', kOptionEnableKeyboard,
                enabled: enabled, fakeValue: fakeValue),
            if (isWindows)
              _OptionCheckBox(
                  context, 'Enable remote printer', kOptionEnableRemotePrinter,
                  enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(context, 'Enable clipboard', kOptionEnableClipboard,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(
                context, 'Enable file transfer', kOptionEnableFileTransfer,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(context, 'Enable audio', kOptionEnableAudio,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(context, 'Enable camera', kOptionEnableCamera,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(context, 'Enable terminal', kOptionEnableTerminal,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(
                context, 'Enable TCP tunneling', kOptionEnableTunnel,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(
                context, 'Enable remote restart', kOptionEnableRemoteRestart,
                enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(
                context, 'Enable recording session', kOptionEnableRecordSession,
                enabled: enabled, fakeValue: fakeValue),
            if (isWindows)
              _OptionCheckBox(context, 'Enable blocking user input',
                  kOptionEnableBlockInput,
                  enabled: enabled, fakeValue: fakeValue),
            if (bind.mainSupportedPrivacyModeImpls() != '[]')
              _OptionCheckBox(
                  context, 'Enable privacy mode', kOptionEnablePrivacyMode,
                  enabled: enabled, fakeValue: fakeValue),
            _OptionCheckBox(context, 'Enable remote configuration modification',
                kOptionAllowRemoteConfigModification,
                enabled: enabled, fakeValue: fakeValue),
          ],
        ),
      ]);
    }

    return tmpWrapper();
  }

  Widget password(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: ((context, model, child) {
          List<String> passwordKeys = [
            kUseTemporaryPassword,
            kUsePermanentPassword,
            kUseBothPasswords,
          ];
          List<String> passwordValues = [
            translate('Use one-time password'),
            translate('Use permanent password'),
            translate('Use both passwords'),
          ];
          bool tmpEnabled = model.verificationMethod != kUsePermanentPassword;
          bool permEnabled = model.verificationMethod != kUseTemporaryPassword;
          String currentValue =
              passwordValues[passwordKeys.indexOf(model.verificationMethod)];
          List<Widget> radios = passwordValues
              .map((value) => _Radio<String>(
                    context,
                    value: value,
                    groupValue: currentValue,
                    label: value,
                    onChanged: locked
                        ? null
                        : ((value) async {
                            callback() async {
                              await model.setVerificationMethod(
                                  passwordKeys[passwordValues.indexOf(value)]);
                              await model.updatePasswordModel();
                            }

                            if (value ==
                                    passwordValues[passwordKeys
                                        .indexOf(kUsePermanentPassword)] &&
                                (await bind.mainGetCommon(
                                        key: "permanent-password-set")) !=
                                    "true") {
                              if (isChangePermanentPasswordDisabled()) {
                                await callback();
                                return;
                              }
                              setPasswordDialog(notEmptyCallback: callback);
                            } else {
                              await callback();
                            }
                          }),
                  ))
              .toList();

          var onChanged = tmpEnabled && !locked
              ? (value) {
                  if (value != null) {
                    () async {
                      await model.setTemporaryPasswordLength(value.toString());
                      await model.updatePasswordModel();
                    }();
                  }
                }
              : null;
          List<Widget> lengthRadios = ['6', '8', '10']
              .map((value) => GestureDetector(
                    child: Row(
                      children: [
                        Radio(
                            value: value,
                            groupValue: model.temporaryPasswordLength,
                            onChanged: onChanged),
                        Text(
                          value,
                          style: TextStyle(
                              color: disabledTextColor(
                                  context, onChanged != null)),
                        ),
                      ],
                    ).paddingOnly(right: 10),
                    onTap: () => onChanged?.call(value),
                  ))
              .toList();

          final isOptFixedNumOTP =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isNumOPTChangable = !isOptFixedNumOTP && tmpEnabled && !locked;
          final numericOneTimePassword = GestureDetector(
            child: InkWell(
                child: Row(
              children: [
                Checkbox(
                        value: model.allowNumericOneTimePassword,
                        onChanged: isNumOPTChangable
                            ? (bool? v) {
                                model.switchAllowNumericOneTimePassword();
                              }
                            : null)
                    .marginOnly(right: 5),
                Expanded(
                    child: Text(
                  translate('Numeric one-time password'),
                  style: TextStyle(
                      color: disabledTextColor(context, isNumOPTChangable)),
                ))
              ],
            )),
            onTap: isNumOPTChangable
                ? () => model.switchAllowNumericOneTimePassword()
                : null,
          ).marginOnly(left: _kContentHSubMargin - 5);

          final modeKeys = <String>[
            'password',
            'click',
            defaultOptionApproveMode
          ];
          final modeValues = [
            translate('Accept sessions via password'),
            translate('Accept sessions via click'),
            translate('Accept sessions via both'),
          ];
          var modeInitialKey = model.approveMode;
          if (!modeKeys.contains(modeInitialKey)) {
            modeInitialKey = defaultOptionApproveMode;
          }
          final usePassword = model.approveMode != 'click';

          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          return _Card(title: 'Password', children: [
            ComboBox(
              enabled: !locked && !isApproveModeFixed,
              keys: modeKeys,
              values: modeValues,
              initialKey: modeInitialKey,
              onChanged: (key) => model.setApproveMode(key),
            ).marginOnly(left: _kContentHMargin),
            if (usePassword) radios[0],
            if (usePassword)
              _SubLabeledWidget(
                  context,
                  'One-time password length',
                  Row(
                    children: [
                      ...lengthRadios,
                    ],
                  ),
                  enabled: tmpEnabled && !locked),
            if (usePassword) numericOneTimePassword,
            if (usePassword) radios[1],
            if (usePassword && !isChangePermanentPasswordDisabled())
              _SubButton('Set permanent password', setPasswordDialog,
                  permEnabled && !locked),
            // if (usePassword)
            //   hide_cm(!locked).marginOnly(left: _kContentHSubMargin - 6),
            if (usePassword) radios[2],
          ]);
        })));
  }

  Widget more(BuildContext context) {
    bool enabled = !locked;
    return _Card(title: 'Security', children: [
      shareRdp(context, enabled),
      _OptionCheckBox(context, 'Deny LAN discovery', 'enable-lan-discovery',
          reverse: true, enabled: enabled),
      ...directIp(context),
      whitelist(),
      idWhitelist(),
      ...autoDisconnect(context),
      _OptionCheckBox(context, 'keep-awake-during-incoming-sessions-label',
          kOptionKeepAwakeDuringIncomingSessions,
          reverse: false, enabled: enabled),
      if (bind.mainIsInstalled())
        _OptionCheckBox(context, 'allow-only-conn-window-open-tip',
            'allow-only-conn-window-open',
            reverse: false, enabled: enabled),
      if (bind.mainIsInstalled() && !isUnlockPinDisabled()) unlockPin()
    ]);
  }

  shareRdp(BuildContext context, bool enabled) {
    onChanged(bool b) async {
      await bind.mainSetShareRdp(enable: b);
      setState(() {});
    }

    bool value = bind.mainIsShareRdp();
    return Offstage(
      offstage: !(isWindows && bind.mainIsInstalled()),
      child: GestureDetector(
          child: Row(
            children: [
              Checkbox(
                      value: value,
                      onChanged: enabled ? (_) => onChanged(!value) : null)
                  .marginOnly(right: 5),
              Expanded(
                child: Text(translate('Enable RDP session sharing'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled))),
              )
            ],
          ).marginOnly(left: _kCheckBoxLeftMargin),
          onTap: enabled ? () => onChanged(!value) : null),
    );
  }

  List<Widget> directIp(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(context, 'Enable direct IP access', kOptionDirectServer,
          update: update, enabled: !locked),
      () {
        // Simple temp wrapper for PR check
        tmpWrapper() {
          bool enabled = option2bool(kOptionDirectServer,
              bind.mainGetOptionSync(key: kOptionDirectServer));
          if (!enabled) applyEnabled.value = false;
          controller.text =
              bind.mainGetOptionSync(key: kOptionDirectAccessPort);
          final isOptFixed = isOptionFixed(kOptionDirectAccessPort);
          return Offstage(
            offstage: !enabled,
            child: _SubLabeledWidget(
              context,
              'Port',
              Row(children: [
                SizedBox(
                  width: 95,
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !locked && !isOptFixed,
                    onChanged: (_) => applyEnabled.value = true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(
                          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                    ],
                    decoration: const InputDecoration(
                      hintText: '21118',
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ).workaroundFreezeLinuxMint().marginOnly(right: 15),
                ),
                Obx(() => ElevatedButton(
                      onPressed: applyEnabled.value &&
                              enabled &&
                              !locked &&
                              !isOptFixed
                          ? () async {
                              applyEnabled.value = false;
                              await bind.mainSetOption(
                                  key: kOptionDirectAccessPort,
                                  value: controller.text);
                            }
                          : null,
                      child: Text(
                        translate('Apply'),
                      ),
                    ))
              ]),
              enabled: enabled && !locked && !isOptFixed,
            ),
          );
        }

        return tmpWrapper();
      }(),
    ];
  }

  Widget whitelist() {
    bool enabled = !locked;
    // Simple temp wrapper for PR check
    tmpWrapper() {
      RxBool hasWhitelist = whitelistNotEmpty().obs;
      update() async {
        hasWhitelist.value = whitelistNotEmpty();
      }

      onChanged(bool? checked) async {
        changeWhiteList(callback: update);
      }

      final isOptFixed = isOptionFixed(kOptionWhitelist);
      return GestureDetector(
        child: Tooltip(
          message: translate('whitelist_tip'),
          child: Obx(() => Row(
                children: [
                  Checkbox(
                          value: hasWhitelist.value,
                          onChanged: enabled && !isOptFixed ? onChanged : null)
                      .marginOnly(right: 5),
                  Offstage(
                    offstage: !hasWhitelist.value,
                    child: MouseRegion(
                      child: const Icon(Icons.warning_amber_rounded,
                              color: Color.fromARGB(255, 255, 204, 0))
                          .marginOnly(right: 5),
                      cursor: SystemMouseCursors.click,
                    ),
                  ),
                  Expanded(
                      child: Text(
                    translate('Use IP Whitelisting'),
                    style:
                        TextStyle(color: disabledTextColor(context, enabled)),
                  ))
                ],
              )),
        ),
        onTap: enabled
            ? () {
                onChanged(!hasWhitelist.value);
              }
            : null,
      ).marginOnly(left: _kCheckBoxLeftMargin);
    }

    return tmpWrapper();
  }

  Widget idWhitelist() {
    bool enabled = !locked;
    RxBool hasIdWhitelist = idWhitelistNotEmpty().obs;
    update() async {
      hasIdWhitelist.value = idWhitelistNotEmpty();
    }

    onChanged(bool? checked) async {
      changeIdWhiteList(callback: update);
    }

    final isOptFixed = isOptionFixed(kOptionIdWhitelist);
    return GestureDetector(
      child: Tooltip(
        message: translate('id_whitelist_tip'),
        child: Obx(() => Row(
              children: [
                Checkbox(
                        value: hasIdWhitelist.value,
                        onChanged: enabled && !isOptFixed ? onChanged : null)
                    .marginOnly(right: 5),
                Offstage(
                  offstage: !hasIdWhitelist.value,
                  child: MouseRegion(
                    child: const Icon(Icons.warning_amber_rounded,
                            color: Color.fromARGB(255, 255, 204, 0))
                        .marginOnly(right: 5),
                    cursor: SystemMouseCursors.click,
                  ),
                ),
                Expanded(
                    child: Text(
                  translate('Use ID whitelisting'),
                  style: TextStyle(color: disabledTextColor(context, enabled)),
                ))
              ],
            )),
      ),
      onTap: enabled
          ? () {
              onChanged(!hasIdWhitelist.value);
            }
          : null,
    ).marginOnly(left: _kCheckBoxLeftMargin);
  }

  Widget hide_cm(bool enabled) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: (context, model, child) {
          final enableHideCm = model.approveMode == 'password' &&
              model.verificationMethod == kUsePermanentPassword;
          onHideCmChanged(bool? b) {
            if (b != null) {
              bind.mainSetOption(
                  key: 'allow-hide-cm', value: bool2option('allow-hide-cm', b));
            }
          }

          return Tooltip(
              message: enableHideCm ? "" : translate('hide_cm_tip'),
              child: GestureDetector(
                onTap:
                    enableHideCm ? () => onHideCmChanged(!model.hideCm) : null,
                child: Row(
                  children: [
                    Checkbox(
                            value: model.hideCm,
                            onChanged: enabled && enableHideCm
                                ? onHideCmChanged
                                : null)
                        .marginOnly(right: 5),
                    Expanded(
                      child: Text(
                        translate('Hide connection management window'),
                        style: TextStyle(
                            color: disabledTextColor(
                                context, enabled && enableHideCm)),
                      ),
                    ),
                  ],
                ),
              ));
        }));
  }

  List<Widget> autoDisconnect(BuildContext context) {
    TextEditingController controller = TextEditingController();
    update(bool v) => setState(() {});
    RxBool applyEnabled = false.obs;
    return [
      _OptionCheckBox(
          context, 'auto_disconnect_option_tip', kOptionAllowAutoDisconnect,
          update: update, enabled: !locked),
      () {
        bool enabled = option2bool(kOptionAllowAutoDisconnect,
            bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
        if (!enabled) applyEnabled.value = false;
        controller.text =
            bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
        final isOptFixed = isOptionFixed(kOptionAutoDisconnectTimeout);
        return Offstage(
          offstage: !enabled,
          child: _SubLabeledWidget(
            context,
            'Timeout in minutes',
            Row(children: [
              SizedBox(
                width: 95,
                child: TextField(
                  controller: controller,
                  enabled: enabled && !locked && !isOptFixed,
                  onChanged: (_) => applyEnabled.value = true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(
                        r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$')),
                  ],
                  decoration: const InputDecoration(
                    hintText: '10',
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                ).workaroundFreezeLinuxMint().marginOnly(right: 15),
              ),
              Obx(() => ElevatedButton(
                    onPressed:
                        applyEnabled.value && enabled && !locked && !isOptFixed
                            ? () async {
                                applyEnabled.value = false;
                                await bind.mainSetOption(
                                    key: kOptionAutoDisconnectTimeout,
                                    value: controller.text);
                              }
                            : null,
                    child: Text(
                      translate('Apply'),
                    ),
                  ))
            ]),
            enabled: enabled && !locked && !isOptFixed,
          ),
        );
      }(),
    ];
  }

  Widget unlockPin() {
    bool enabled = !locked;
    RxString unlockPin = bind.mainGetUnlockPin().obs;
    update() async {
      unlockPin.value = bind.mainGetUnlockPin();
    }

    onChanged(bool? checked) async {
      changeUnlockPinDialog(unlockPin.value, update);
    }

    final isOptFixed = isOptionFixed(kOptionWhitelist);
    return GestureDetector(
      child: Obx(() => Row(
            children: [
              Checkbox(
                      value: unlockPin.isNotEmpty,
                      onChanged: enabled && !isOptFixed ? onChanged : null)
                  .marginOnly(right: 5),
              Expanded(
                  child: Text(
                translate('Unlock with PIN'),
                style: TextStyle(color: disabledTextColor(context, enabled)),
              ))
            ],
          )),
      onTap: enabled
          ? () {
              onChanged(!unlockPin.isNotEmpty);
            }
          : null,
    ).marginOnly(left: _kCheckBoxLeftMargin);
  }
}

class _Network extends StatefulWidget {
  const _Network({Key? key}) : super(key: key);

  @override
  State<_Network> createState() => _NetworkState();
}

class _NetworkState extends State<_Network> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool locked = !isWeb && bind.mainIsInstalled();

  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(controller: scrollController, children: [
      _lock(locked, 'Unlock Network Settings', () {
        locked = false;
        setState(() => {});
      }),
      preventMouseKeyBuilder(
        block: locked,
        child: Column(children: [
          network(context),
        ]),
      ),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget network(BuildContext context) {
    final hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    final hideProxy =
        isWeb || bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    final hideWebSocket = isWeb ||
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y';

    if (hideServer && hideProxy && hideWebSocket) {
      return Offstage();
    }

    // Helper function to create network setting ListTiles
    Widget listTile({
      required IconData icon,
      required String title,
      VoidCallback? onTap,
      Widget? trailing,
      bool showTooltip = false,
      String tooltipMessage = '',
    }) {
      final titleWidget = showTooltip
          ? Row(
              children: [
                Tooltip(
                  waitDuration: Duration(milliseconds: 1000),
                  message: translate(tooltipMessage),
                  child: Row(
                    children: [
                      Text(
                        translate(title),
                        style: TextStyle(fontSize: _kContentFontSize),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.help_outline,
                        size: 14,
                        color: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Text(
              translate(title),
              style: TextStyle(fontSize: _kContentFontSize),
            );

      return ListTile(
        leading: Icon(icon, color: _accentColor),
        title: titleWidget,
        enabled: !locked,
        onTap: onTap,
        trailing: trailing,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        minLeadingWidth: 0,
        horizontalTitleGap: 10,
      );
    }

    Widget switchWidget(IconData icon, String title, String tooltipMessage,
            String optionKey) =>
        listTile(
          icon: icon,
          title: title,
          showTooltip: true,
          tooltipMessage: tooltipMessage,
          trailing: Switch(
            value: mainGetBoolOptionSync(optionKey),
            onChanged: locked || isOptionFixed(optionKey)
                ? null
                : (value) {
                    mainSetBoolOption(optionKey, value);
                    setState(() {});
                  },
          ),
        );

    final outgoingOnly = bind.isOutgoingOnly();

    if (!bind.isIncomingOnly()) {
      Widget tile(IconData icone, String titulo, String desc,
          {VoidCallback? onTap, Widget? trailing}) {
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: locked ? null : onTap,
          child: Opacity(
            opacity: locked ? 0.55 : 1,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: H3Cores.fundo,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: H3Cores.linha),
              ),
              child: Row(children: [
                Icon(icone, size: 22, color: H3Cores.apagado),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(translate(titulo),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: H3Cores.texto)),
                        const SizedBox(height: 2),
                        Text(desc,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: H3Cores.apagado)),
                      ]),
                ),
                const SizedBox(width: 10),
                trailing ??
                    Icon(Icons.chevron_right, size: 20, color: H3Cores.apagado),
              ]),
            ),
          ),
        );
      }

      Widget interruptor(IconData icone, String titulo, String desc, bool valor,
          bool fixa, Future<void> Function(bool) alterar) {
        return tile(icone, titulo, desc,
            onTap: fixa ? null : () async {
                    await alterar(!valor);
                    setState(() {});
                  },
            trailing: Switch(
              value: valor,
              activeColor: Colors.white,
              activeTrackColor: H3Cores.destaque,
              inactiveTrackColor: H3Cores.linha2,
              inactiveThumbColor: Colors.white,
              onChanged: locked || fixa
                  ? null
                  : (v) async {
                      await alterar(v);
                      setState(() {});
                    },
            ));
      }

      final servidor = <Widget>[
        if (!hideServer)
          tile(Icons.dns_outlined, 'ID/Relay Server',
              'Servidor que registra este computador e intermedia as conexões.',
              onTap: () => showServerSettings(gFFI.dialogManager, setState)),
        if (!hideProxy)
          tile(Icons.network_ping_outlined, 'Socks5/Http(s) Proxy',
              'Encaminha o tráfego por um proxy Socks5 ou HTTP(S).',
              onTap: changeSocks5Proxy),
      ];
      final conexao = <Widget>[
        if (!hideWebSocket)
          interruptor(
              Icons.web_asset_outlined,
              'Use WebSocket',
              'Conecta por WebSocket, útil em redes que bloqueiam o tráfego padrão.',
              mainGetBoolOptionSync(kOptionAllowWebSocket),
              isOptionFixed(kOptionAllowWebSocket),
              (v) => mainSetBoolOption(kOptionAllowWebSocket, v)),
        if (!isWeb)
          futureBuilder(
            future: bind.mainIsUsingPublicServer(),
            hasData: (isUsingPublicServer) {
              if (isUsingPublicServer) return const Offstage();
              return Column(children: [
                interruptor(
                    Icons.no_encryption_outlined,
                    'Allow insecure TLS fallback',
                    'Permite continuar se a verificação TLS falhar. Use só se necessário.',
                    mainGetBoolOptionSync(kOptionAllowInsecureTLSFallback),
                    isOptionFixed(kOptionAllowInsecureTLSFallback),
                    (v) => mainSetBoolOption(
                        kOptionAllowInsecureTLSFallback, v)),
                if (!outgoingOnly)
                  interruptor(
                      Icons.lan_outlined,
                      'Disable UDP',
                      'Desativa o UDP e usa só TCP nas conexões.',
                      bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y',
                      isOptionFixed(kOptionDisableUdp),
                      (v) => bind.mainSetOption(
                          key: kOptionDisableUdp, value: v ? 'Y' : 'N')),
              ]);
            },
          ),
      ];
      return _colunasSimples([
        if (servidor.isNotEmpty)
          _Card(title: 'Servidor e proxy', children: servidor),
        _Card(title: 'Conexão', children: conexao),
      ]);
    }

    final divider = const Divider(height: 1, indent: 16, endIndent: 16);
    return _Card(
      title: 'Network',
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideServer)
                listTile(
                  icon: Icons.dns_outlined,
                  title: 'ID/Relay Server',
                  onTap: () => showServerSettings(gFFI.dialogManager, setState),
                ),
              if (!hideProxy && !hideServer) divider,
              if (!hideProxy)
                listTile(
                  icon: Icons.network_ping_outlined,
                  title: 'Socks5/Http(s) Proxy',
                  onTap: changeSocks5Proxy,
                ),
              if (!hideWebSocket && (!hideServer || !hideProxy)) divider,
              if (!hideWebSocket)
                switchWidget(
                    Icons.web_asset_outlined,
                    'Use WebSocket',
                    '${translate('websocket_tip')}\n\n${translate('server-oss-not-support-tip')}',
                    kOptionAllowWebSocket),
              if (!isWeb)
                futureBuilder(
                  future: bind.mainIsUsingPublicServer(),
                  hasData: (isUsingPublicServer) {
                    if (isUsingPublicServer) {
                      return Offstage();
                    } else {
                      return Column(
                        children: [
                          if (!hideServer || !hideProxy || !hideWebSocket)
                            divider,
                          switchWidget(
                              Icons.no_encryption_outlined,
                              'Allow insecure TLS fallback',
                              'allow-insecure-tls-fallback-tip',
                              kOptionAllowInsecureTLSFallback),
                          if (!outgoingOnly) divider,
                          if (!outgoingOnly)
                            listTile(
                              icon: Icons.lan_outlined,
                              title: 'Disable UDP',
                              showTooltip: true,
                              tooltipMessage:
                                  '${translate('disable-udp-tip')}\n\n${translate('server-oss-not-support-tip')}',
                              trailing: Switch(
                                value: bind.mainGetOptionSync(
                                        key: kOptionDisableUdp) ==
                                    'Y',
                                onChanged:
                                    locked || isOptionFixed(kOptionDisableUdp)
                                        ? null
                                        : (value) async {
                                            await bind.mainSetOption(
                                                key: kOptionDisableUdp,
                                                value: value ? 'Y' : 'N');
                                            setState(() {});
                                          },
                              ),
                            ),
                        ],
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Display extends StatefulWidget {
  const _Display({Key? key}) : super(key: key);

  @override
  State<_Display> createState() => _DisplayState();
}

class _DisplayState extends State<_Display> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return _duasColunas(scrollController, [
      viewStyle(context),
      scrollStyle(context),
      imageQuality(context),
      codec(context),
      if (isDesktop) trackpadSpeed(context),
      if (!isWeb) privacyModeImpl(context),
      other(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget viewStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionViewStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(key: kOptionViewStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionViewStyle);
    return _Card(title: 'Default View Style', children: [
      _Radio(context,
          value: kRemoteViewStyleOriginal,
          groupValue: groupValue,
          label: 'Scale original',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteViewStyleAdaptive,
          groupValue: groupValue,
          label: 'Scale adaptive',
          onChanged: isOptFixed ? null : onChanged),
    ]);
  }

  Widget scrollStyle(BuildContext context) {
    final isOptFixed = isOptionFixed(kOptionScrollStyle);
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionScrollStyle, value: value);
      setState(() {});
    }

    final groupValue = bind.mainGetUserDefaultOption(key: kOptionScrollStyle);

    onEdgeScrollEdgeThicknessChanged(double value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionEdgeScrollEdgeThickness, value: value.round().toString());
      setState(() {});
    }

    return _Card(title: 'Default Scroll Style', children: [
      _Radio(context,
          value: kRemoteScrollStyleAuto,
          groupValue: groupValue,
          label: 'ScrollAuto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteScrollStyleBar,
          groupValue: groupValue,
          label: 'Scrollbar',
          onChanged: isOptFixed ? null : onChanged),
      if (!isWeb) ...[
        _Radio(context,
            value: kRemoteScrollStyleEdge,
            groupValue: groupValue,
            label: 'ScrollEdge',
            onChanged: isOptFixed ? null : onChanged),
        Offstage(
            offstage: groupValue != kRemoteScrollStyleEdge,
            child: EdgeThicknessControl(
              value: double.tryParse(bind.mainGetUserDefaultOption(
                      key: kOptionEdgeScrollEdgeThickness)) ??
                  100.0,
              onChanged: isOptionFixed(kOptionEdgeScrollEdgeThickness)
                  ? null
                  : onEdgeScrollEdgeThicknessChanged,
            )),
      ],
    ]);
  }

  Widget imageQuality(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionImageQuality, value: value);
      setState(() {});
    }

    final isOptFixed = isOptionFixed(kOptionImageQuality);
    final groupValue = bind.mainGetUserDefaultOption(key: kOptionImageQuality);
    return _Card(title: 'Default Image Quality', children: [
      _Radio(context,
          value: kRemoteImageQualityBest,
          groupValue: groupValue,
          label: 'Good image quality',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityBalanced,
          groupValue: groupValue,
          label: 'Balanced',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityLow,
          groupValue: groupValue,
          label: 'Optimize reaction time',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: kRemoteImageQualityCustom,
          groupValue: groupValue,
          label: 'Custom',
          onChanged: isOptFixed ? null : onChanged),
      Offstage(
        offstage: groupValue != kRemoteImageQualityCustom,
        child: customImageQualitySetting(),
      )
    ]);
  }

  Widget trackpadSpeed(BuildContext context) {
    final initSpeed =
        (int.tryParse(bind.mainGetUserDefaultOption(key: kKeyTrackpadSpeed)) ??
            kDefaultTrackpadSpeed);
    final curSpeed = SimpleWrapper(initSpeed);
    void onDebouncer(int v) {
      bind.mainSetUserDefaultOption(
          key: kKeyTrackpadSpeed, value: v.toString());
      // It's better to notify all sessions that the default speed is changed.
      // But it may also be ok to take effect in the next connection.
    }

    return _Card(title: 'Default trackpad speed', children: [
      TrackpadSpeedWidget(
        value: curSpeed,
        onDebouncer: onDebouncer,
      ),
    ]);
  }

  Widget codec(BuildContext context) {
    onChanged(String value) async {
      await bind.mainSetUserDefaultOption(
          key: kOptionCodecPreference, value: value);
      setState(() {});
    }

    final groupValue =
        bind.mainGetUserDefaultOption(key: kOptionCodecPreference);
    var hwRadios = [];
    final isOptFixed = isOptionFixed(kOptionCodecPreference);
    try {
      final Map codecsJson = jsonDecode(bind.mainSupportedHwdecodings());
      final h264 = codecsJson['h264'] ?? false;
      final h265 = codecsJson['h265'] ?? false;
      if (h264) {
        hwRadios.add(_Radio(context,
            value: 'h264',
            groupValue: groupValue,
            label: 'H264',
            onChanged: isOptFixed ? null : onChanged));
      }
      if (h265) {
        hwRadios.add(_Radio(context,
            value: 'h265',
            groupValue: groupValue,
            label: 'H265',
            onChanged: isOptFixed ? null : onChanged));
      }
    } catch (e) {
      debugPrint("failed to parse supported hwdecodings, err=$e");
    }
    return _Card(title: 'Default Codec', children: [
      _Radio(context,
          value: 'auto',
          groupValue: groupValue,
          label: 'Auto',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'vp8',
          groupValue: groupValue,
          label: 'VP8',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'vp9',
          groupValue: groupValue,
          label: 'VP9',
          onChanged: isOptFixed ? null : onChanged),
      _Radio(context,
          value: 'av1',
          groupValue: groupValue,
          label: 'AV1',
          onChanged: isOptFixed ? null : onChanged),
      ...hwRadios,
    ]);
  }

  Widget privacyModeImpl(BuildContext context) {
    final supportedPrivacyModeImpls = bind.mainSupportedPrivacyModeImpls();
    late final List<dynamic> privacyModeImpls;
    try {
      privacyModeImpls = jsonDecode(supportedPrivacyModeImpls);
    } catch (e) {
      debugPrint('failed to parse supported privacy mode impls, err=$e');
      return Offstage();
    }
    if (privacyModeImpls.length < 2) {
      return Offstage();
    }

    final key = 'privacy-mode-impl-key';
    onChanged(String value) async {
      await bind.mainSetOption(key: key, value: value);
      setState(() {});
    }

    String groupValue = bind.mainGetOptionSync(key: key);
    if (groupValue.isEmpty) {
      groupValue = bind.mainDefaultPrivacyModeImpl();
    }
    return _Card(
      title: 'Privacy mode',
      children: privacyModeImpls.map((impl) {
        final d = impl as List<dynamic>;
        return _Radio(context,
            value: d[0] as String,
            groupValue: groupValue,
            label: d[1] as String,
            onChanged: onChanged);
      }).toList(),
    );
  }

  Widget otherRow(String label, String key) {
    final value = getOtherDefaultSettingOption(key) == 'Y';
    final isOptFixed = isOtherDefaultSettingReadOnly(key);
    onChanged(bool b) async {
      await setOtherDefaultSettingOption(
        key,
        b ? 'Y' : (key == kOptionEnableFileCopyPaste ? 'N' : defaultOptionNo),
      );
      setState(() {});
    }

    if (!bind.isIncomingOnly()) {
      return GestureDetector(
        onTap: isOptFixed ? null : () => onChanged(!value),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          decoration: BoxDecoration(
            color: H3Cores.fundo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: H3Cores.linha),
          ),
          child: Row(children: [
            Expanded(
              child: Text(translate(label),
                  style: TextStyle(
                      fontSize: 14,
                      color: isOptFixed ? H3Cores.apagado : H3Cores.texto)),
            ),
            Transform.scale(
              scale: 0.82,
              child: Switch(
                value: value,
                activeColor: Colors.white,
                activeTrackColor: H3Cores.destaque,
                inactiveTrackColor: H3Cores.linha2,
                inactiveThumbColor: Colors.white,
                onChanged: isOptFixed ? null : onChanged,
              ),
            ),
          ]),
        ),
      );
    }
    return GestureDetector(
        child: Row(
          children: [
            Checkbox(
                    value: value,
                    onChanged: isOptFixed ? null : (_) => onChanged(!value))
                .marginOnly(right: 5),
            Expanded(
              child: Text(translate(label)),
            )
          ],
        ).marginOnly(left: _kCheckBoxLeftMargin),
        onTap: isOptFixed ? null : () => onChanged(!value));
  }

  Widget other(BuildContext context) {
    final children =
        otherDefaultSettings().map((e) => otherRow(e.$1, e.$2)).toList();
    return _Card(title: 'Other Default Options', children: children);
  }
}

class _Account extends StatefulWidget {
  const _Account({Key? key}) : super(key: key);

  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(
      controller: scrollController,
      children: [
        Obx(() => gFFI.userModel.userName.value.isEmpty
            ? (bind.isIncomingOnly()
                ? _Card(title: 'Account', children: [accountAction()])
                : Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            H3Cores.destaque.withOpacity(0.14),
                            H3Cores.painel
                          ]),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: H3Cores.linha2),
                    ),
                    child: Column(children: [
                      Icon(Icons.account_circle_outlined,
                          size: 56, color: H3Cores.destaque),
                      const SizedBox(height: 14),
                      Text('Entre na sua conta H3 Suporte',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: H3Cores.texto)),
                      const SizedBox(height: 6),
                      Text(
                          'Guarde seus computadores na conta e conecte com um clique, de qualquer lugar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: H3Cores.apagado)),
                      const SizedBox(height: 18),
                      ElevatedButton(
                          style: _estiloBotaoH3(),
                          onPressed: () => loginDialog(),
                          child: Text(translate('Login'))),
                    ]),
                  ))
            : ContaConteudo(
                onConfigLocal: () =>
                    DesktopSettingPage.switch2page(SettingsTabKey.general))),
      ],
    ).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget accountAction() {
    return Obx(() => _Button(
        gFFI.userModel.userName.value.isEmpty
            ? 'Login'
            : '${translate('Logout')} (${gFFI.userModel.accountLabelWithHandle})',
        () => {
              gFFI.userModel.userName.value.isEmpty
                  ? loginDialog()
                  : logOutConfirmDialog()
            }));
  }

  Widget useInfo() {
    return Obx(() => Offstage(
          offstage: gFFI.userModel.userName.value.isEmpty,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Builder(builder: (context) {
              final avatarWidget = _buildUserAvatar();
              return Row(
                children: [
                  if (avatarWidget != null) avatarWidget,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          gFFI.userModel.displayNameOrUserName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SelectionArea(
                          child: Text(
                            '@${gFFI.userModel.userName.value}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        )).marginOnly(left: 18, top: 16);
  }

  Widget? _buildUserAvatar() {
    // Resolve relative avatar path at display time
    final avatar =
        bind.mainResolveAvatarUrl(avatar: gFFI.userModel.avatar.value);
    return buildAvatarWidget(
      avatar: avatar,
      size: 44,
    );
  }
}

class _Checkbox extends StatefulWidget {
  final String label;
  final bool Function() getValue;
  final Future<void> Function(bool) setValue;

  const _Checkbox(
      {Key? key,
      required this.label,
      required this.getValue,
      required this.setValue})
      : super(key: key);

  @override
  State<_Checkbox> createState() => _CheckboxState();
}

class _CheckboxState extends State<_Checkbox> {
  var value = false;

  @override
  initState() {
    super.initState();
    value = widget.getValue();
  }

  @override
  Widget build(BuildContext context) {
    onChanged(bool b) async {
      await widget.setValue(b);
      setState(() {
        value = widget.getValue();
      });
    }

    return GestureDetector(
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (_) => onChanged(!value),
          ).marginOnly(right: 5),
          Expanded(
            child: Text(translate(widget.label)),
          )
        ],
      ).marginOnly(left: _kCheckBoxLeftMargin),
      onTap: () => onChanged(!value),
    );
  }
}

class _Printer extends StatefulWidget {
  const _Printer({super.key});

  @override
  State<_Printer> createState() => __PrinterState();
}

class __PrinterState extends State<_Printer> {
  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return ListView(controller: scrollController, children: [
      outgoing(context),
      incoming(context),
    ]).marginOnly(bottom: _kListViewBottomMargin);
  }

  Widget outgoing(BuildContext context) {
    final isSupportPrinterDriver =
        bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true';

    Widget tipOsNotSupported() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-os-requirement-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipClientNotInstalled() {
      return Align(
        alignment: Alignment.topLeft,
        child:
            Text(translate('printer-requires-installed-{$appName}-client-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    Widget tipPrinterNotInstalled() {
      final failedMsg = ''.obs;
      platformFFI.registerEventHandler(
          'install-printer-res', 'install-printer-res', (evt) async {
        if (evt['success'] as bool) {
          setState(() {});
        } else {
          failedMsg.value = evt['msg'] as String;
        }
      }, replace: true);
      return Column(children: [
        Obx(
          () => failedMsg.value.isNotEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(translate('printer-{$appName}-not-installed-tip'))
                      .marginOnly(bottom: 10.0),
                ),
        ),
        Obx(
          () => failedMsg.value.isEmpty
              ? Offstage()
              : Align(
                  alignment: Alignment.topLeft,
                  child: Text(failedMsg.value,
                          style: DefaultTextStyle.of(context)
                              .style
                              .copyWith(color: Colors.red))
                      .marginOnly(bottom: 10.0)),
        ),
        _Button('Install {$appName} Printer', () {
          failedMsg.value = '';
          bind.mainSetCommon(key: 'install-printer', value: '');
        })
      ]).marginOnly(left: _kCardLeftMargin, bottom: 2.0);
    }

    Widget tipReady() {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(translate('printer-{$appName}-ready-tip')),
      ).marginOnly(left: _kCardLeftMargin);
    }

    final installed = bind.mainIsInstalled();
    // `is-printer-installed` may fail, but it's rare case.
    // Add additional error message here if it's really needed.
    final isPrinterInstalled =
        bind.mainGetCommonSync(key: 'is-printer-installed') == 'true';

    final List<Widget> children = [];
    if (!isSupportPrinterDriver) {
      children.add(tipOsNotSupported());
    } else {
      children.addAll([
        if (!installed) tipClientNotInstalled(),
        if (installed && !isPrinterInstalled) tipPrinterNotInstalled(),
        if (installed && isPrinterInstalled) tipReady()
      ]);
    }
    return _Card(title: 'Outgoing Print Jobs', children: children);
  }

  Widget incoming(BuildContext context) {
    onRadioChanged(String value) async {
      await bind.mainSetLocalOption(
          key: kKeyPrinterIncomingJobAction, value: value);
      setState(() {});
    }

    PrinterOptions printerOptions = PrinterOptions.load();
    return _Card(title: 'Incoming Print Jobs', children: [
      _Radio(context,
          value: kValuePrinterIncomingJobDismiss,
          groupValue: printerOptions.action,
          label: 'Dismiss',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobDefault,
          groupValue: printerOptions.action,
          label: 'use-the-default-printer-tip',
          onChanged: onRadioChanged),
      _Radio(context,
          value: kValuePrinterIncomingJobSelected,
          groupValue: printerOptions.action,
          label: 'use-the-selected-printer-tip',
          onChanged: onRadioChanged),
      if (printerOptions.printerNames.isNotEmpty)
        ComboBox(
          initialKey: printerOptions.printerName,
          keys: printerOptions.printerNames,
          values: printerOptions.printerNames,
          enabled: printerOptions.action == kValuePrinterIncomingJobSelected,
          onChanged: (value) async {
            await bind.mainSetLocalOption(
                key: kKeyPrinterSelected, value: value);
            setState(() {});
          },
        ).marginOnly(left: 10),
      _OptionCheckBox(
        context,
        'auto-print-tip',
        kKeyPrinterAllowAutoPrint,
        isServer: false,
        enabled: printerOptions.action != kValuePrinterIncomingJobDismiss,
      )
    ]);
  }
}

class _About extends StatefulWidget {
  const _About({Key? key}) : super(key: key);

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  Widget _infoTile(IconData icone, String rotulo, String valor,
      {bool mono = false, bool copiar = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: H3Cores.painel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: H3Cores.linha),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  H3Cores.destaque.withOpacity(0.28),
                  H3Cores.destaque.withOpacity(0.08)
                ]),
          ),
          child: Icon(icone, size: 18, color: H3Cores.destaque),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo,
                style: TextStyle(fontSize: 12, color: H3Cores.apagado)),
            const SizedBox(height: 3),
            SelectionArea(
              child: Text(valor,
                  style: TextStyle(
                      fontSize: mono ? 11.5 : 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: mono ? 'monospace' : null,
                      color: H3Cores.texto)),
            ),
          ]),
        ),
        if (copiar)
          Tooltip(
            message: 'Copiar',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Clipboard.setData(ClipboardData(text: valor));
                showToast(translate('Copied'));
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.copy_rounded, size: 17, color: H3Cores.apagado),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _linkBotao(IconData icone, String rotulo, String url) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => launchUrlString(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: H3Cores.painel2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: H3Cores.linha2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 18, color: H3Cores.destaque),
          const SizedBox(width: 10),
          Text(rotulo,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: H3Cores.texto)),
          const SizedBox(width: 8),
          Icon(Icons.open_in_new, size: 14, color: H3Cores.apagado),
        ]),
      ),
    );
  }

  Widget _sobreH3(ScrollController c, String version, String buildDate,
      String fingerprint, String myId, String license) {
    final ano = DateTime.now().toString().substring(0, 4);
    return ListView(
        controller: c,
        padding: const EdgeInsets.fromLTRB(15, 6, 15, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    H3Cores.destaque.withOpacity(0.16),
                    H3Cores.painel
                  ]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: H3Cores.linha2),
            ),
            child: Row(children: [
              loadIcon(72),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('H3 Suporte',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: H3Cores.texto)),
                      const SizedBox(height: 6),
                      Text('Acesso remoto seguro, da H3 Informática.',
                          style:
                              TextStyle(fontSize: 13, color: H3Cores.apagado)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                            color: H3Cores.destaque.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('Versão $version',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: H3Cores.destaque)),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, caixa) {
            const gap = 14.0;
            final cols = caixa.maxWidth >= 1000 ? 4 : (caixa.maxWidth >= 640 ? 2 : 1);
            final itens = <Widget>[
              _infoTile(Icons.tag, translate('Version'), version, copiar: true),
              _infoTile(Icons.event_outlined, translate('Build Date'), buildDate),
              _infoTile(Icons.fingerprint, translate('ID'), myId, copiar: true),
              if (!isWeb)
                _infoTile(Icons.verified_outlined, translate('Fingerprint'),
                    fingerprint,
                    mono: true,
                    copiar: true),
            ];
            final linhas = <Widget>[];
            for (var i = 0; i < itens.length; i += cols) {
              final fatia = itens.skip(i).take(cols).toList();
              linhas.add(Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
                child: IntrinsicHeight(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < cols; j++) ...[
                          if (j > 0) const SizedBox(width: gap),
                          Expanded(
                              child: j < fatia.length
                                  ? fatia[j]
                                  : const SizedBox.shrink()),
                        ],
                      ]),
                ),
              ));
            }
            return Column(children: linhas);
          }),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _linkBotao(Icons.language, translate('Website'), 'https://h3info.com'),
            _linkBotao(Icons.code, 'Licença AGPL-3.0 e código-fonte',
                'https://github.com/helivander/h3suporte'),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: H3Cores.painel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: H3Cores.linha),
            ),
            child: SelectionArea(
              child: Text('Copyright © $ano H3 Informatica.\n$license',
                  style: TextStyle(
                      fontSize: 12, height: 1.5, color: H3Cores.apagado)),
            ),
          ),
        ]);
  }

  @override
  Widget build(BuildContext context) {
    return futureBuilder(future: () async {
      final license = await bind.mainGetLicense();
      final version = await bind.mainGetVersion();
      final buildDate = await bind.mainGetBuildDate();
      final fingerprint = await bind.mainGetFingerprint();
      final myId = await bind.mainGetMyId();
      return {
        'license': license,
        'version': version,
        'buildDate': buildDate,
        'fingerprint': fingerprint,
        'myId': myId
      };
    }(), hasData: (data) {
      final license = data['license'].toString();
      final version = data['version'].toString();
      final buildDate = data['buildDate'].toString();
      final fingerprint = data['fingerprint'].toString();
      final myId = data['myId'].toString();
      const linkStyle = TextStyle(decoration: TextDecoration.underline);
      final scrollController = ScrollController();
      if (!bind.isIncomingOnly()) {
        return _sobreH3(scrollController, version, buildDate, fingerprint,
            myId, license);
      }
      return SingleChildScrollView(
        controller: scrollController,
        child: _Card(title: 'Sobre o H3 Suporte', children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 8.0,
              ),
              SelectionArea(
                  child: Text('${translate('Version')}: $version')
                      .marginSymmetric(vertical: 4.0)),
              SelectionArea(
                  child: Text('${translate('Build Date')}: $buildDate')
                      .marginSymmetric(vertical: 4.0)),
              if (!isWeb)
                SelectionArea(
                    child: Text('${translate('Fingerprint')}: $fingerprint')
                        .marginSymmetric(vertical: 4.0)),
              SelectionArea(
                  child: Text('${translate('ID')}: $myId')
                      .marginSymmetric(vertical: 4.0)),
              InkWell(
                  onTap: () {
                    launchUrlString('https://h3info.com');
                  },
                  child: Text(
                    translate('Website'),
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),
              InkWell(
                  onTap: () {
                    launchUrlString(
                        'https://github.com/helivander/h3suporte');
                  },
                  child: Text(
                    'Licença AGPL-3.0 e código-fonte',
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),
              Container(
                decoration: bind.isIncomingOnly()
                    ? const BoxDecoration(color: Color(0xFF2c8cff))
                    : BoxDecoration(
                        color: H3Cores.painel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: H3Cores.linha2)),
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                child: SelectionArea(
                    child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Copyright © ${DateTime.now().toString().substring(0, 4)} H3 Informatica.\n$license',
                            style: const TextStyle(color: Colors.white),
                          ),
                          if (bind.isIncomingOnly())
                            Text(
                              translate('Slogan_tip'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            )
                        ],
                      ),
                    ),
                  ],
                )),
              ).marginSymmetric(vertical: 4.0)
            ],
          ).marginOnly(left: _kContentHMargin)
        ]),
      );
    });
  }
}

//#endregion

//#region components

/// Como [_duasColunas], mas sem rolagem própria: para uso dentro de outra rolagem.
Widget _colunasSimples(List<Widget> itens) {
  if (bind.isIncomingOnly()) return Column(children: itens);
  return LayoutBuilder(builder: (context, caixa) {
    final n = caixa.maxWidth >= 1500 ? 3 : (caixa.maxWidth >= 900 ? 2 : 1);
    if (n == 1) return Column(children: itens);
    final cols = List.generate(n, (_) => <Widget>[]);
    for (var i = 0; i < itens.length; i++) {
      cols[i % n].add(itens[i]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final c in cols) Expanded(child: Column(children: c)),
    ]).paddingOnly(right: 15);
  });
}

/// Em janelas largas distribui os cartões em duas colunas; nas estreitas (ou no modo só receber) mantém a lista.
Widget _duasColunas(ScrollController c, List<Widget> itens) {
  if (bind.isIncomingOnly()) return ListView(controller: c, children: itens);
  return LayoutBuilder(builder: (context, caixa) {
    final n = caixa.maxWidth >= 1500 ? 3 : (caixa.maxWidth >= 900 ? 2 : 1);
    if (n == 1) return ListView(controller: c, children: itens);
    final cols = List.generate(n, (_) => <Widget>[]);
    for (var i = 0; i < itens.length; i++) {
      cols[i % n].add(itens[i]);
    }
    return SingleChildScrollView(
      controller: c,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final col in cols) Expanded(child: Column(children: col)),
      ]).paddingOnly(right: 15),
    );
  });
}

IconData _iconeCard(String titulo) {
  switch (titulo) {
    case 'Permissions':
      return Icons.verified_user_outlined;
    case 'Password':
      return Icons.key_outlined;
    case '2FA':
      return Icons.phonelink_lock_outlined;
    case 'ID':
      return Icons.badge_outlined;
    case 'Language':
      return Icons.language;
    case 'Theme':
      return Icons.palette_outlined;
    case 'Service':
      return Icons.dns_outlined;
    case 'Account':
      return Icons.person_outline;
    case 'Display':
      return Icons.desktop_windows_outlined;
    case 'Network':
      return Icons.lan_outlined;
    case 'Servidor e proxy':
      return Icons.dns_outlined;
    case 'Conexão':
      return Icons.cable_outlined;
    default:
      return Icons.tune;
  }
}

// ignore: non_constant_identifier_names
Widget _Card(
    {required String title,
    required List<Widget> children,
    List<Widget>? title_suffix}) {
  final incoming = bind.isIncomingOnly();
  return Row(
    children: [
      Flexible(
        child: SizedBox(
          width: incoming ? _kCardFixedWidth : double.infinity,
          child: Container(
            decoration: incoming
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [H3Cores.painel2, H3Cores.painel]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: H3Cores.linha)),
            child: incoming
                ? Card(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text(
                              translate(title),
                              textAlign: TextAlign.start,
                              style: TextStyle(fontSize: _kTitleFontSize),
                            )),
                            ...?title_suffix
                          ],
                        ).marginOnly(
                            left: _kContentHMargin, top: 10, bottom: 10),
                        ...children.map(
                            (e) => e.marginOnly(top: 4, right: _kContentHMargin)),
                      ],
                    ).marginOnly(bottom: 10),
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    H3Cores.destaque.withOpacity(0.28),
                                    H3Cores.destaque.withOpacity(0.08)
                                  ]),
                            ),
                            child: Icon(_iconeCard(title),
                                size: 18, color: H3Cores.destaque),
                          ),
                          Expanded(
                              child: Text(
                            translate(title),
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          )),
                          ...?title_suffix
                        ],
                      ).marginOnly(left: _kContentHMargin, top: 14, bottom: 10),
                      Divider(height: 1, color: H3Cores.linha)
                          .marginOnly(bottom: 6),
                      ...children
                          .map((e) => e.marginOnly(top: 4, right: _kContentHMargin)),
                    ],
                  ).marginOnly(bottom: 12),
          ).marginOnly(left: _kCardLeftMargin, top: 15),
        ),
      ),
    ],
  );
}

// ignore: non_constant_identifier_names
Widget _OptionCheckBox(
  BuildContext context,
  String label,
  String key, {
  Function(bool)? update,
  bool reverse = false,
  bool enabled = true,
  Icon? checkedIcon,
  bool? fakeValue,
  bool isServer = true,
  bool Function()? optGetter,
  Future<void> Function(String, bool)? optSetter,
  // Optional widget rendered between the label and the trailing space.
  Widget? trailing,
}) {
  getOpt() => optGetter != null
      ? optGetter()
      : (isServer
          ? mainGetBoolOptionSync(key)
          : mainGetLocalBoolOptionSync(key));
  bool value = getOpt();
  final isOptFixed = isOptionFixed(key);
  if (reverse) value = !value;
  var ref = value.obs;
  onChanged(option) async {
    if (option != null) {
      if (reverse) option = !option;
      final setter =
          optSetter ?? (isServer ? mainSetBoolOption : mainSetLocalBoolOption);
      await setter(key, option);
      final readOption = getOpt();
      if (reverse) {
        ref.value = !readOption;
      } else {
        ref.value = readOption;
      }
      update?.call(readOption);
    }
  }

  if (fakeValue != null) {
    ref.value = fakeValue;
    enabled = false;
  }

  if (!bind.isIncomingOnly()) {
    final rotulo = Text(
      translate(label),
      style: TextStyle(
          fontSize: 14,
          color: enabled && !isOptFixed ? H3Cores.texto : H3Cores.apagado),
    );
    return GestureDetector(
      onTap: enabled && !isOptFixed ? () => onChanged(!ref.value) : null,
      child: Obx(
        () => Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          decoration: BoxDecoration(
            color: H3Cores.fundo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: H3Cores.linha),
          ),
          child: Row(children: [
            Offstage(
              offstage: !ref.value || checkedIcon == null,
              child: checkedIcon?.marginOnly(right: 8),
            ),
            if (trailing == null)
              Expanded(child: rotulo)
            else ...[
              Flexible(child: rotulo),
              trailing,
              const Spacer(),
            ],
            Transform.scale(
              scale: 0.82,
              child: Switch(
                value: ref.value,
                activeColor: Colors.white,
                activeTrackColor: H3Cores.destaque,
                inactiveTrackColor: H3Cores.linha2,
                inactiveThumbColor: Colors.white,
                onChanged: enabled && !isOptFixed ? onChanged : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  return GestureDetector(
    child: Obx(
      () => Row(
        children: [
          Checkbox(
                  value: ref.value,
                  onChanged: enabled && !isOptFixed ? onChanged : null)
              .marginOnly(right: 5),
          Offstage(
            offstage: !ref.value || checkedIcon == null,
            child: checkedIcon?.marginOnly(right: 5),
          ),
          // Without `trailing`, keep the original Expanded(Text) layout.
          if (trailing == null)
            Expanded(
                child: Text(
              translate(label),
              style: TextStyle(color: disabledTextColor(context, enabled)),
            ))
          else ...[
            Flexible(
              child: Text(
                translate(label),
                style: TextStyle(color: disabledTextColor(context, enabled)),
              ),
            ),
            trailing,
            const Spacer(),
          ],
        ],
      ),
    ).marginOnly(left: _kCheckBoxLeftMargin),
    onTap: enabled && !isOptFixed
        ? () {
            onChanged(!ref.value);
          }
        : null,
  );
}

// ignore: non_constant_identifier_names
Widget _Radio<T>(BuildContext context,
    {required T value,
    required T groupValue,
    required String label,
    required Function(T value)? onChanged,
    bool autoNewLine = true}) {
  final onChange2 = onChanged != null
      ? (T? value) {
          if (value != null) {
            onChanged(value);
          }
        }
      : null;
  if (!bind.isIncomingOnly()) {
    final on = value == groupValue;
    final ativo = onChange2 != null;
    return GestureDetector(
      onTap: () => onChange2?.call(value),
      child: Opacity(
        opacity: ativo ? 1 : 0.55,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: on
                ? LinearGradient(colors: [
                    H3Cores.destaque.withOpacity(0.18),
                    H3Cores.destaque.withOpacity(0.05)
                  ])
                : null,
            color: on ? null : H3Cores.fundo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: on ? H3Cores.destaque.withOpacity(0.7) : H3Cores.linha,
                width: on ? 1.4 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Text(translate(label),
                  overflow: autoNewLine ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: on ? H3Cores.texto : H3Cores.apagado)),
            ),
            Icon(on ? Icons.check_circle : Icons.circle_outlined,
                size: 20, color: on ? H3Cores.destaque : H3Cores.linha2),
          ]),
        ),
      ),
    );
  }
  return GestureDetector(
    child: Row(
      children: [
        Radio<T>(value: value, groupValue: groupValue, onChanged: onChange2),
        Expanded(
          child: Text(translate(label),
                  overflow: autoNewLine ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: _kContentFontSize,
                      color: disabledTextColor(context, onChange2 != null)))
              .marginOnly(left: 5),
        ),
      ],
    ).marginOnly(left: _kRadioLeftMargin),
    onTap: () => onChange2?.call(value),
  );
}

class WaylandCard extends StatefulWidget {
  const WaylandCard({Key? key}) : super(key: key);

  @override
  State<WaylandCard> createState() => _WaylandCardState();
}

class _WaylandCardState extends State<WaylandCard> {
  final restoreTokenKey = 'wayland-restore-token';
  static const _kClearShortcutsInhibitorEventKey =
      'clear-gnome-shortcuts-inhibitor-permission-res';
  final _clearShortcutsInhibitorFailedMsg = ''.obs;
  // Don't show the shortcuts permission reset button for now.
  // Users can change it manually:
  //   "Settings" -> "Apps" -> "RustDesk" -> "Permissions" -> "Inhibit Shortcuts".
  // For resetting(clearing) the permission from the portal permission store, you can
  // use (replace <desktop-id> with the RustDesk desktop file ID):
  //   busctl --user call org.freedesktop.impl.portal.PermissionStore \
  //   /org/freedesktop/impl/portal/PermissionStore org.freedesktop.impl.portal.PermissionStore \
  //   DeletePermission sss "gnome" "shortcuts-inhibitor" "<desktop-id>"
  // On a native install this is typically "rustdesk.desktop"; on Flatpak it is usually
  // the exported desktop ID derived from the Flatpak app-id (e.g. "com.rustdesk.RustDesk.desktop").
  //
  // We may add it back in the future if needed.
  final showResetInhibitorPermission = false;

  @override
  void initState() {
    super.initState();
    if (showResetInhibitorPermission) {
      platformFFI.registerEventHandler(
          _kClearShortcutsInhibitorEventKey, _kClearShortcutsInhibitorEventKey,
          (evt) async {
        if (!mounted) return;
        if (evt['success'] == true) {
          setState(() {});
        } else {
          _clearShortcutsInhibitorFailedMsg.value =
              evt['msg'] as String? ?? 'Unknown error';
        }
      });
    }
  }

  @override
  void dispose() {
    if (showResetInhibitorPermission) {
      platformFFI.unregisterEventHandler(
          _kClearShortcutsInhibitorEventKey, _kClearShortcutsInhibitorEventKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return futureBuilder(
      future: bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "get"),
      hasData: (restoreToken) {
        final hasShortcutsPermission = showResetInhibitorPermission &&
            bind.mainGetCommonSync(
                    key: "has-gnome-shortcuts-inhibitor-permission") ==
                "true";

        final children = [
          if (restoreToken.isNotEmpty)
            _buildClearScreenSelection(context, restoreToken),
          if (hasShortcutsPermission)
            _buildClearShortcutsInhibitorPermission(context),
        ];
        return Offstage(
          offstage: children.isEmpty,
          child: _Card(title: 'Wayland', children: children),
        );
      },
    );
  }

  Widget _buildClearScreenSelection(BuildContext context, String restoreToken) {
    onConfirm() async {
      final msg = await bind.mainHandleWaylandScreencastRestoreToken(
          key: restoreTokenKey, value: "clear");
      gFFI.dialogManager.dismissAll();
      if (msg.isNotEmpty) {
        msgBox(gFFI.sessionId, 'custom-nocancel', 'Error', msg, '',
            gFFI.dialogManager);
      } else {
        setState(() {});
      }
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm_clear_Wayland_screen_selection_tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return _Button(
      'Clear Wayland screen selection',
      showConfirmMsgBox,
      tip: 'clear_Wayland_screen_selection_tip',
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.all<Color>(
            Theme.of(context).colorScheme.error.withOpacity(0.75)),
      ),
    );
  }

  Widget _buildClearShortcutsInhibitorPermission(BuildContext context) {
    onConfirm() {
      _clearShortcutsInhibitorFailedMsg.value = '';
      bind.mainSetCommon(
          key: "clear-gnome-shortcuts-inhibitor-permission", value: "");
      gFFI.dialogManager.dismissAll();
    }

    showConfirmMsgBox() => msgBoxCommon(
            gFFI.dialogManager,
            'Confirmation',
            Text(
              translate('confirm-clear-shortcuts-inhibitor-permission-tip'),
            ),
            [
              dialogButton('OK', onPressed: onConfirm),
              dialogButton('Cancel',
                  onPressed: () => gFFI.dialogManager.dismissAll())
            ]);

    return Column(children: [
      Obx(
        () => _clearShortcutsInhibitorFailedMsg.value.isEmpty
            ? Offstage()
            : Align(
                alignment: Alignment.topLeft,
                child: Text(_clearShortcutsInhibitorFailedMsg.value,
                        style: DefaultTextStyle.of(context)
                            .style
                            .copyWith(color: Colors.red))
                    .marginOnly(bottom: 10.0)),
      ),
      _Button(
        'Reset keyboard shortcuts permission',
        showConfirmMsgBox,
        tip: 'clear-shortcuts-inhibitor-permission-tip',
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(
              Theme.of(context).colorScheme.error.withOpacity(0.75)),
        ),
      ),
    ]);
  }
}

ButtonStyle? _estiloBotaoH3() => bind.isIncomingOnly()
    ? null
    : ElevatedButton.styleFrom(
        backgroundColor: H3Cores.destaque,
        foregroundColor: H3Cores.destaqueTinta,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      );

// ignore: non_constant_identifier_names
Widget _Button(String label, Function() onPressed,
    {bool enabled = true, String? tip, ButtonStyle? style}) {
  style ??= _estiloBotaoH3();
  var button = ElevatedButton(
    onPressed: enabled ? onPressed : null,
    child: Text(
      translate(label),
    ).marginSymmetric(horizontal: 15),
    style: style,
  );
  StatefulWidget child;
  if (tip == null) {
    child = button;
  } else {
    child = Tooltip(message: translate(tip), child: button);
  }
  return Row(children: [
    child,
  ]).marginOnly(left: _kContentHMargin);
}

// ignore: non_constant_identifier_names
Widget _SubButton(String label, Function() onPressed, [bool enabled = true]) {
  return Row(
    children: [
      ElevatedButton(
        style: _estiloBotaoH3(),
        onPressed: enabled ? onPressed : null,
        child: Text(
          translate(label),
        ).marginSymmetric(horizontal: 15),
      ),
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

// ignore: non_constant_identifier_names
Widget _SubLabeledWidget(BuildContext context, String label, Widget child,
    {bool enabled = true}) {
  return Row(
    children: [
      Text(
        '${translate(label)}: ',
        style: TextStyle(color: disabledTextColor(context, enabled)),
      ),
      SizedBox(
        width: 10,
      ),
      child,
    ],
  ).marginOnly(left: _kContentHSubMargin);
}

Widget _lock(
  bool locked,
  String label,
  Function() onUnlock,
) {
  if (locked && !bind.isIncomingOnly()) {
    Future<void> desbloquear() async {
      final unlockPin = bind.mainGetUnlockPin();
      if (unlockPin.isEmpty || isUnlockPinDisabled()) {
        bool checked = await callMainCheckSuperUserPermission();
        if (checked) onUnlock();
      } else {
        checkUnlockPinDialog(unlockPin, onUnlock);
      }
    }

    return Row(children: [
      Flexible(
        child: SizedBox(
          width: double.infinity,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: H3Cores.aviso.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: H3Cores.aviso.withOpacity(0.45)),
            ),
            child: Row(children: [
              Icon(Icons.lock_outline, size: 26, color: H3Cores.aviso),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                    'Estas configurações estão bloqueadas. Desbloqueie para alterar.',
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: H3Cores.texto)),
              ),
              const SizedBox(width: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: desbloquear,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(colors: [
                      H3Cores.destaque,
                      H3Cores.destaque.withOpacity(0.78)
                    ]),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_open_outlined,
                        size: 17, color: H3Cores.destaqueTinta),
                    const SizedBox(width: 8),
                    Text(translate(label),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: H3Cores.destaqueTinta)),
                  ]),
                ),
              ),
            ]),
          ).marginOnly(left: _kCardLeftMargin, top: 10),
        ),
      ),
    ]);
  }
  return Offstage(
      offstage: !locked,
      child: Row(
        children: [
          Flexible(
            child: SizedBox(
              width: _kCardFixedWidth,
              child: Card(
                child: ElevatedButton(
                  child: SizedBox(
                      height: 25,
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.security_sharp,
                              size: 20,
                            ),
                            Text(translate(label)).marginOnly(left: 5),
                          ]).marginSymmetric(vertical: 2)),
                  onPressed: () async {
                    final unlockPin = bind.mainGetUnlockPin();
                    if (unlockPin.isEmpty || isUnlockPinDisabled()) {
                      bool checked = await callMainCheckSuperUserPermission();
                      if (checked) {
                        onUnlock();
                      }
                    } else {
                      checkUnlockPinDialog(unlockPin, onUnlock);
                    }
                  },
                ).marginSymmetric(horizontal: 2, vertical: 4),
              ).marginOnly(left: _kCardLeftMargin),
            ).marginOnly(top: 10),
          ),
        ],
      ));
}

_LabeledTextField(
    BuildContext context,
    String label,
    TextEditingController controller,
    String errorText,
    bool enabled,
    bool secure) {
  return Table(
    columnWidths: const {
      0: FixedColumnWidth(150),
      1: FlexColumnWidth(),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    children: [
      TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${translate(label)}:',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                color: disabledTextColor(context, enabled),
              ),
            ),
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            obscureText: secure,
            autocorrect: false,
            decoration: InputDecoration(
              errorText: errorText.isNotEmpty ? errorText : null,
            ),
            style: TextStyle(
              color: disabledTextColor(context, enabled),
            ),
          ).workaroundFreezeLinuxMint(),
        ],
      ),
    ],
  ).marginOnly(bottom: 8);
}

class _CountDownButton extends StatefulWidget {
  _CountDownButton({
    Key? key,
    required this.text,
    required this.second,
    required this.onPressed,
  }) : super(key: key);
  final String text;
  final VoidCallback? onPressed;
  final int second;

  @override
  State<_CountDownButton> createState() => _CountDownButtonState();
}

class _CountDownButtonState extends State<_CountDownButton> {
  bool _isButtonDisabled = false;

  late int _countdownSeconds = widget.second;

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_countdownSeconds <= 0) {
        setState(() {
          _isButtonDisabled = false;
        });
        timer.cancel();
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isButtonDisabled
          ? null
          : () {
              widget.onPressed?.call();
              setState(() {
                _isButtonDisabled = true;
                _countdownSeconds = widget.second;
              });
              _startCountdownTimer();
            },
      child: Text(
        _isButtonDisabled ? '$_countdownSeconds s' : translate(widget.text),
      ),
    );
  }
}

// Tappable row that pushes the shortcut configuration page.
class _ShortcutsConfigureRow extends StatelessWidget {
  // ignore: unused_element
  const _ShortcutsConfigureRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const DesktopKeyboardShortcutsPage(),
        ));
      },
      child: Row(
        children: [
          Expanded(
            child: Text(translate('Configure shortcuts...')),
          ),
          Icon(Icons.arrow_forward_ios,
                  size: 16, color: disabledTextColor(context, true))
              .marginOnly(right: 4),
        ],
      ).marginOnly(
        left: _kCheckBoxLeftMargin,
        top: 6,
        bottom: 6,
      ),
    );
  }
}

//#endregion

//#region dialogs

void changeSocks5Proxy() async {
  var socks = await bind.mainGetSocks();

  String proxy = '';
  String proxyMsg = '';
  String username = '';
  String password = '';
  if (socks.length == 3) {
    proxy = socks[0];
    username = socks[1];
    password = socks[2];
  }
  var proxyController = TextEditingController(text: proxy);
  var userController = TextEditingController(text: username);
  var pwdController = TextEditingController(text: password);
  RxBool obscure = true.obs;

  // proxy settings
  // The following option is a not real key, it is just used for custom client advanced settings.
  const String optionProxyUrl = "proxy-url";
  final isOptFixed = isOptionFixed(optionProxyUrl);

  var isInProgress = false;
  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      setState(() {
        proxyMsg = '';
        isInProgress = true;
      });
      cancel() {
        setState(() {
          isInProgress = false;
        });
      }

      proxy = proxyController.text.trim();
      username = userController.text.trim();
      password = pwdController.text.trim();

      if (proxy.isNotEmpty) {
        String domainPort = proxy;
        if (domainPort.contains('://')) {
          domainPort = domainPort.split('://')[1];
        }
        proxyMsg = translate(await bind.mainTestIfValidServer(
            server: domainPort, testWithProxy: false));
        if (proxyMsg.isEmpty) {
          // ignore
        } else {
          cancel();
          return;
        }
      }
      await bind.mainSetSocks(
          proxy: proxy, username: username, password: password);
      close();
    }

    return CustomAlertDialog(
      title: Text(translate('Socks5/Http(s) Proxy')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 140),
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          children: [
                            Text(
                              translate('Server'),
                            ).marginOnly(right: 4),
                            Tooltip(
                              waitDuration: Duration(milliseconds: 0),
                              message: translate("default_proxy_tip"),
                              child: Icon(
                                Icons.help_outline_outlined,
                                size: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        )).marginOnly(right: 10),
                  ),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      errorText: proxyMsg.isNotEmpty ? proxyMsg : null,
                      labelText: isMobile ? translate('Server') : null,
                      helperText:
                          isMobile ? translate("default_proxy_tip") : null,
                      helperMaxLines: isMobile ? 3 : null,
                    ),
                    controller: proxyController,
                    autofocus: true,
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Username")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: TextField(
                    controller: userController,
                    decoration: InputDecoration(
                      labelText: isMobile ? translate('Username') : null,
                    ),
                    enabled: !isOptFixed,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ).marginOnly(bottom: 8),
            Row(
              children: [
                if (!isMobile)
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      child: Text(
                        '${translate("Password")}:',
                        textAlign: TextAlign.right,
                      ).marginOnly(right: 10)),
                Expanded(
                  child: Obx(() => TextField(
                        obscureText: obscure.value,
                        decoration: InputDecoration(
                            labelText: isMobile ? translate('Password') : null,
                            suffixIcon: IconButton(
                                onPressed: () => obscure.value = !obscure.value,
                                icon: Icon(obscure.value
                                    ? Icons.visibility_off
                                    : Icons.visibility))),
                        controller: pwdController,
                        enabled: !isOptFixed,
                        maxLength: bind.mainMaxEncryptLen(),
                      ).workaroundFreezeLinuxMint()),
                ),
              ],
            ),
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress)
              const LinearProgressIndicator().marginOnly(top: 8),
          ],
        ),
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        if (!isOptFixed) dialogButton('OK', onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

//#endregion
