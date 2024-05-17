import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/widgets/scaffold.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'models/models.dart';
import 'common/common.dart';

class GlobalState {
  Timer? timer;
  Function? healthcheckLockDebounce;
  Timer? groupsUpdateTimer;
  Function? updateCurrentDelayDebounce;
  PageController? pageController;
  final navigatorKey = GlobalKey<NavigatorState>();
  final Map<int, String?> packageNameMap = {};
  late AppController appController;
  GlobalKey<CommonScaffoldState> homeScaffoldKey = GlobalKey();
  List<Function> updateFunctionLists = [];
  List<NavigationItem> currentNavigationItems = [];
  bool updatePackagesLock = false;
  bool healthcheckLock = false;

  startListenUpdate() {
    if (timer != null && timer!.isActive == true) return;
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      for (final function in updateFunctionLists) {
        function();
      }
    });
  }

  stopListenUpdate() {
    if (timer == null || timer?.isActive == false) return;
    timer?.cancel();
  }

  Future<String> updateClashConfig({
    required ClashConfig clashConfig,
    required Config config,
    bool isPatch = true,
  }) async {
    final profilePath = await appPath.getProfilePath(config.currentProfileId);
    debugPrint("update config");
    return clashCore.updateConfig(UpdateConfigParams(
      profilePath: profilePath,
      config: clashConfig,
      isPatch: isPatch,
      isCompatible: config.isCompatible,
    ));
  }

  updateCoreVersionInfo(AppState appState) {
    appState.versionInfo = clashCore.getVersionInfo();
  }

  Future<void> startSystemProxy({
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    final args =
        config.isAccessControl ? json.encode(config.accessControl) : null;
    await proxyManager.startProxy(
      port: clashConfig.mixedPort,
      args: args,
    );
    startListenUpdate();
  }

  Future<void> stopSystemProxy() async {
    await proxyManager.stopProxy();
    stopListenUpdate();
  }

  applyProfile({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    final res = await updateClashConfig(
      clashConfig: clashConfig,
      config: config,
      isPatch: false,
    );
    if (res.isNotEmpty) return Result.error(message: res);
    await updateGroups(appState);
    changeProxy(
      appState: appState,
      config: config,
      clashConfig: clashConfig,
    );
  }

  init({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) async {
    appState.isInit = clashCore.isInit;
    if (!appState.isInit) {
      appState.isInit = await clashService.init(
        config: config,
        clashConfig: clashConfig,
      );
    }
    if (!appState.isInit) return;
    await applyProfile(
      appState: appState,
      config: config,
      clashConfig: clashConfig,
    );
    updateCoreVersionInfo(appState);
  }

  changeProxy({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (config.profiles.isEmpty) {
        stopSystemProxy();
        return;
      }
      config.currentSelectedMap.forEach((key, value) {
        clashCore.changeProxy(
          ChangeProxyParams(
            groupName: key,
            proxyName: value,
          ),
        );
      });
    });
  }

  updatePackages(AppState appState) async {
    if (appState.packages.isEmpty && updatePackagesLock == false) {
      updatePackagesLock = true;
      appState.packages = await app?.getPackages() ?? [];
      updatePackagesLock = false;
    }
  }

  updateNavigationItems({
    required AppState appState,
    required Config config,
    required ClashConfig clashConfig,
  }) {
    final group = appState.currentGroups;
    final hasProfile = config.profiles.isNotEmpty;
    appState.navigationItems = navigation.getItems(
      openLogs: config.openLogs,
      hasProxies: group.isNotEmpty && hasProfile,
    );
  }

  Future<void> updateGroups(AppState appState) async {
    appState.groups = await clashCore.getProxiesGroups();
  }

  showMessage({
    required String title,
    required InlineSpan message,
    Function()? onTab,
  }) {
    showCommonDialog(
      child: Builder(
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 300,
              child: RichText(
                text: TextSpan(
                    style: Theme.of(context).textTheme.labelLarge,
                    children: [message]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: onTab ??
                    () {
                      Navigator.of(context).pop();
                    },
                child: Text(appLocalizations.confirm),
              )
            ],
          );
        },
      ),
    );
  }

  showCommonDialog<T>({
    required Widget child,
  }) async {
    return await showModal<T>(
      context: navigatorKey.currentState!.context,
      configuration: const FadeScaleTransitionConfiguration(
        barrierColor: Colors.black38,
      ),
      builder: (_) => child,
      filter: appConstant.filter,
    );
  }

  checkUpdate(Function()? onTab) async {
    final result = await Request.checkForUpdate();
    if (result.type == ResultType.success) {
      showMessage(
        title: appLocalizations.discovery,
        message: TextSpan(
          text: result.data,
        ),
        onTab: onTab,
      );
    }
  }

  updateTraffic({
    AppState? appState,
    required Config config,
  }) {
    final traffic = clashCore.getTraffic();
    if (appState != null) {
      appState.addTraffic(traffic);
    }
    if (Platform.isAndroid) {
      final currentProfile = config.currentProfile;
      if (currentProfile == null) return;
      proxyManager.startForeground(
        title: currentProfile.label ?? currentProfile.id,
        content: "$traffic",
      );
    }
  }

  showSnackBar(
    BuildContext context, {
    required String message,
    SnackBarAction? action,
  }) {
    final width = context.width;
    EdgeInsets margin;
    if (width < 600) {
      margin = const EdgeInsets.only(
        bottom: 96,
        right: 16,
        left: 16,
      );
    } else {
      margin = EdgeInsets.only(
        bottom: 16,
        left: 16,
        right: width - 316,
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        action: action,
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        margin: margin,
      ),
    );
  }

  void updateCurrentDelay(
      String? proxyName,
      ) {
    updateCurrentDelayDebounce ??= debounce<Function(String?)>((proxyName) {
      if (proxyName != null) {
        debugPrint("[delay]=====> $proxyName");
        clashCore.delay(
          proxyName,
        );
      }
    });
    updateCurrentDelayDebounce!([proxyName]);
  }

}

final globalState = GlobalState();
