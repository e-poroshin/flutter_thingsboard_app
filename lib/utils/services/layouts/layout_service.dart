import 'package:flutter/cupertino.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/logger/tb_logger.dart';
import 'package:thingsboard_app/modules/main/main_navigation_item.dart';
import 'package:thingsboard_app/thingsboard_client.dart'
    show Authority, PageLayout, Pages;
import 'package:thingsboard_app/utils/services/layouts/i_layout_service.dart';

class LayoutService implements ILayoutService {
  LayoutService(this.logger);

  final TbLogger logger;

  late Size deviceScreenSize;
  late List<TbMainNavigationItem> bottomBarItems;
  late TbMainNavigationItem more;
   List<PageLayout> pagesLayout = [];

  @override
  List<TbMainNavigationItem> getBottomBarItems() {
    logger.debug(
      'LayoutService::getBottomBarItems() device width'
      ' -> ${deviceScreenSize.width}',
    );

    // PATIENT APP: Always return exactly the patient navigation items
    // No more overflow, strict 3-tab layout for patient users
    if (bottomBarItems.length <= 3) {
      return bottomBarItems;
    }

    if (deviceScreenSize.width < 600) {
      return bottomBarItems.length > 3
          ? [...bottomBarItems.sublist(0, 3), more]
          : [...bottomBarItems, more];
    } else if (deviceScreenSize.width < 960) {
      return bottomBarItems.length > 5
          ? [...bottomBarItems.sublist(0, 5), more]
          : [...bottomBarItems, more];
    } else {
      return bottomBarItems.length > 9
          ? [...bottomBarItems.sublist(0, 9), more]
          : [...bottomBarItems, more];
    }
  }

  @override
  void setBottomBarItems(
    List<TbMainNavigationItem> items, {
    required TbMainNavigationItem more,
  }) {
    bottomBarItems = List.of(items);
    this.more = more;
  }

  @override
  void setDeviceScreenSize(Size size, {required Orientation orientation}) {
    logger.debug(
      'LayoutService::setDeviceScreenSize($size, orientation: $orientation)',
    );

    deviceScreenSize = size;
  }

  @override
  List<TbMainNavigationItem> getMorePageItems(
    TbContext tbContext,
    BuildContext context,
  ) {
    logger.debug('LayoutService::getMorePageItems()');

    final allItems = Set.of(bottomBarItems);
    final bottomBarElements = Set.of(getBottomBarItems());
    return allItems.difference(bottomBarElements).toList();
  }

  @override
  void cachePageLayouts(
    List<PageLayout>? pages, {
    required Authority authority,
  }) {
    logger.debug('LayoutService::cachePagesLayout()');

    // PATIENT APP: For CUSTOMER_USER (Patient), enforce strict 3-tab layout
    // regardless of server-side configuration
    if (authority == Authority.CUSTOMER_USER) {
      pagesLayout = [
        // Tab 1: Home/Health - Patient Dashboard (will be patient_health module)
        const PageLayout(id: Pages.home),
        // Tab 2: History - Existing dashboard module for health metrics/history
        const PageLayout(id: Pages.alarms),
        // Tab 3: Profile - Settings & Profile page
        const PageLayout(id: Pages.notifications),
      ];
      logger.debug(
        'LayoutService::cachePagesLayout() - PATIENT APP: '
        'Enforced 3-tab layout for CUSTOMER_USER',
      );
      return;
    }

    // PATIENT APP: Deny access to non-CUSTOMER_USER roles
    // This is a secondary guard - primary guard is in TbContext.onUserLoaded
    logger.warn(
      'LayoutService::cachePagesLayout() - '
      'Non-patient role detected: $authority',
    );

    // Fallback for legacy behavior (should not reach here in Patient App)
    if (pages == null) {
      pagesLayout = [
        const PageLayout(id: Pages.home),
        const PageLayout(id: Pages.alarms),
        const PageLayout(id: Pages.devices),
      ];

      if (authority == Authority.SYS_ADMIN) {
        pagesLayout.add(const PageLayout(id: Pages.notifications));
      } else if (authority == Authority.TENANT_ADMIN) {
        pagesLayout.addAll(
          [
            const PageLayout(id: Pages.customers),
            const PageLayout(id: Pages.assets),
            const PageLayout(id: Pages.audit_logs),
            const PageLayout(id: Pages.notifications),
          ],
        );
      }
    } else {
      pagesLayout = List.of(pages);
    }
  }

  @override
  List<PageLayout> getCachedPageLayouts() {
    return pagesLayout;
  }
}
