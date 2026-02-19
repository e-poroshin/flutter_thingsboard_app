import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/locator.dart';
import 'package:thingsboard_app/modules/layout_pages/bloc/bloc.dart';
import 'package:thingsboard_app/modules/main/tb_navigation_bar_widget.dart';
import 'package:thingsboard_app/utils/services/layouts/i_layout_service.dart';
import 'package:thingsboard_app/utils/services/notification_service.dart';
import 'package:thingsboard_app/widgets/tb_progress_indicator.dart';

class MainPage extends TbPageWidget {
  MainPage(super.tbContext, {super.key});

  @override
  State<StatefulWidget> createState() => _MainPageState();
}

class _MainPageState extends TbPageState<MainPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _currentIndexNotifier = ValueNotifier(0);
  late TabController _tabController;
  late Orientation orientation;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LayoutPagesBloc>(
      create: (_) => LayoutPagesBloc(
        layoutService: getIt<ILayoutService>(),
        tbContext: tbContext,
      )..add(BottomBarFetchEvent(context)),
      child: BlocBuilder<LayoutPagesBloc, LayoutPagesState>(
        builder: (context, state) {
          switch (state) {
            case BottomBarDataState():
              // Guard: if items is empty, show a loading state instead
              // of crashing on TabController(length: 0).
              if (state.items.isEmpty) {
                return const Scaffold(
                  body: Center(
                    child: TbProgressIndicator(size: 50),
                  ),
                );
              }

              // Clamp the current index to the valid range BEFORE
              // creating the TabController.
              if (_currentIndexNotifier.value >= state.items.length) {
                _currentIndexNotifier.value = state.items.length - 1;
              }

              _tabController = TabController(
                initialIndex: _currentIndexNotifier.value,
                length: state.items.length,
                vsync: this,
              );

              return OrientationBuilder(
                builder: (context, orientation) {
                  if (this.orientation != orientation) {
                    this.orientation = orientation;
                    context.read<LayoutPagesBloc>().add(
                          BottomBarOrientationChangedEvent(
                            orientation,
                            MediaQuery.of(context).size,
                          ),
                        );
                  }

                  return Scaffold(
                    body: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      controller: _tabController,
                      children: state.items.map((e) => e.page).toList(),
                    ),
                    bottomNavigationBar: ValueListenableBuilder<int>(
                      valueListenable: _currentIndexNotifier,
                      builder: (_, _, _) => TbNavigationBarWidget(
                        currentIndex: _currentIndexNotifier.value,
                        onTap: (index) => _setIndex(index),
                        customBottomBarItems: state.items,
                      ),
                    ),
                  );
                },
              );

            default:
              return const Scaffold(
                body: Center(
                  child: TbProgressIndicator(size: 50),
                ),
              );
          }
        },
      ),
    );
  }

  void _setIndex(int index) {
    if (_tabController.index != index) {
     overlayService.hideNotification();
      _tabController.index = index;
      _currentIndexNotifier.value = index;
      tbContext.bottomNavigationTabChangedStream.add(index);
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          orientation = MediaQuery.of(context).orientation;

          // PATIENT APP: Skip TB notification service when using NestJS auth.
          // The TB SDK is not authenticated in NestJS-only mode, so calling
          // getUnreadNotificationsCount() would throw "Unauthorized!".
          if (!tbContext.isNestApiAuthenticated) {
            NotificationService(tbClient, log, tbContext)
                .updateNotificationsCount();
          }
        } catch (e) {
          // Context may be invalid during widget tree transitions
          // Silently ignore to prevent crashes
        }
      }
    });

    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // PATIENT APP: Skip TB notifications when using NestJS auth.
      if (!tbContext.isNestApiAuthenticated) {
        NotificationService(tbClient, log, tbContext)
            .updateNotificationsCount();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Patient Health module DI is now managed at app level, no cleanup needed here
    super.dispose();
  }
}
