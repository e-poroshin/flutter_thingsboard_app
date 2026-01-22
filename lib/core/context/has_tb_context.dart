part of 'tb_context.dart';

mixin HasTbContext {
  late final TbContext _tbContext;
///TODO: refactor 
  // ignore: use_setters_to_change_properties
  void setTbContext(TbContext tbContext) {
    _tbContext = tbContext;
  }

  void setupCurrentState(TbContextState currentState) {
    // Check if the previous state is still mounted before accessing context
    if (_tbContext.currentState != null && _tbContext.currentState!.mounted) {
      try {
        // ignore: deprecated_member_use
        ModalRoute.of(_tbContext.currentState!.context)
            ?.unregisterPopEntry(_tbContext);
      } catch (e) {
        // Context may be invalid during widget tree transitions
        // Silently ignore to prevent crashes
      }
    }
    _tbContext.currentState = currentState;
    if (_tbContext.currentState != null && _tbContext.currentState!.mounted) {
      try {
        // ignore: deprecated_member_use
        ModalRoute.of(_tbContext.currentState!.context)
            ?.registerPopEntry(_tbContext);
      } catch (e) {
        // Context may be invalid during widget tree transitions
        // Silently ignore to prevent crashes
      }
    }
  }

  void setupTbContext(TbContextState currentState) {
    _tbContext = currentState.widget.tbContext;
  }

  TbContext get tbContext => _tbContext;

  TbLogger get log => _tbContext.log;

  ValueNotifier<bool> get loadingNotifier => _tbContext._isLoadingNotifier;

  ThingsboardClient get tbClient => _tbContext.tbClient;

  Future<void> initTbContext() async {
    await _tbContext.init();
  }



 

  void subscribeRouteObserver(TbPageState pageState) {
    if (!pageState.mounted) return;
    try {
      final route = ModalRoute.of(pageState.context);
      if (route != null) {
        _tbContext.routeObserver
            .subscribe(pageState, route as PageRoute);
      }
    } catch (e) {
      // Context may be invalid during widget tree transitions
      // Silently ignore to prevent crashes
    }
  }

  void unsubscribeRouteObserver(TbPageState pageState) {
    _tbContext.routeObserver.unsubscribe(pageState);
  }
}
