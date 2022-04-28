//
//  GKPageScrollView.m
//  GKPageScrollView
//
//  Created by QuintGao on 2018/10/26.
//  Copyright © 2018 QuintGao. All rights reserved.
//

#import "GKPageScrollView.h"
#import "GKPageDefine.h"

@interface GKPageScrollView()<UITableViewDataSource, UITableViewDelegate, GKPageListContainerViewDelegate>

@property (nonatomic, strong) GKPageTableView           *mainTableView;
@property (nonatomic, strong) GKPageListContainerView   *listContainerView;

@property (nonatomic, weak) id<GKPageScrollViewDelegate> delegate;

// 列表存储
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, id<GKPageListViewDelegate>> *validListDict;

// 当前滑动的listView
@property (nonatomic, weak) UIScrollView                *currentListScrollView;

// 是否滑动到临界点，可有偏差
@property (nonatomic, assign) BOOL isCriticalPoint;
// 是否到达临界点，无偏差
@property (nonatomic, assign) BOOL isCeilPoint;
// mainTableView是否可滑动
@property (nonatomic, assign) BOOL isMainCanScroll;
// listScrollView是否可滑动
@property (nonatomic, assign) BOOL isListCanScroll;

// 是否开始拖拽，只有在拖拽中才去处理滑动，解决使用mj_header可能出现的bug
@property (nonatomic, assign) BOOL isBeginDragging;

// 快速切换原点和临界点
@property (nonatomic, assign) BOOL isScrollToOriginal;
@property (nonatomic, assign) BOOL isScrollToCritical;

// 是否加载
@property (nonatomic, assign) BOOL isLoaded;

// headerView的高度
@property (nonatomic, assign) CGFloat headerHeight;

// 临界点
@property (nonatomic, assign) CGFloat criticalPoint;
@property (nonatomic, assign) CGPoint criticalOffset;

@end

@implementation GKPageScrollView

- (instancetype)initWithDelegate:(id<GKPageScrollViewDelegate>)delegate {
    if (self = [super initWithFrame:CGRectZero]) {
        self.delegate = delegate;
        self.ceilPointHeight = GKPAGE_NAVBAR_HEIGHT;
        self.validListDict = [NSMutableDictionary new];
        
        [self initSubviews];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (CGRectEqualToRect(self.mainTableView.frame, self.bounds)) return;
    self.mainTableView.frame = self.bounds;
    if (!self.isLoaded) return;
    [self.mainTableView reloadData];
}

- (void)initSubviews {
    self.isCriticalPoint = NO;
    self.isMainCanScroll = YES;
    self.isListCanScroll = NO;
    
    self.mainTableView = [[GKPageTableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.mainTableView.dataSource = self;
    self.mainTableView.delegate = self;
    self.mainTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.mainTableView.showsVerticalScrollIndicator = NO;
    self.mainTableView.showsHorizontalScrollIndicator = NO;
    [self.mainTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    if (@available(iOS 11.0, *)) {
        self.mainTableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self addSubview:self.mainTableView];
    [self refreshHeaderView];
    
    if ([self shouldLazyLoadListView]) {
        self.mainTableView.horizontalScrollViewList = @[self.listContainerView.collectionView];
    }
}

- (void)setHorizontalScrollViewList:(NSArray *)horizontalScrollViewList {
    _horizontalScrollViewList = horizontalScrollViewList;
    
    NSMutableArray *list = [NSMutableArray arrayWithArray:horizontalScrollViewList];
    if ([self shouldLazyLoadListView]) {
        [list addObject:self.listContainerView.collectionView];
    }
    self.mainTableView.horizontalScrollViewList = list;
}

- (void)setLazyLoadList:(BOOL)lazyLoadList {
    _lazyLoadList = lazyLoadList;
    
    if ([self shouldLazyLoadListView]) {
        self.mainTableView.horizontalScrollViewList = @[self.listContainerView.collectionView];
    }else {
        // listScrollView滑动处理
        [self configListViewScroll];
    }
}

- (void)setMainScrollDisabled:(BOOL)mainScrollDisabled {
    _mainScrollDisabled = mainScrollDisabled;
    
    self.mainTableView.scrollEnabled = !self.mainScrollDisabled;
}

#pragma mark - Public Methods
- (void)refreshHeaderView {
    UIView *headerView = [self.delegate headerViewInPageScrollView:self];
    self.mainTableView.tableHeaderView = headerView;
    self.headerHeight = headerView.frame.size.height;
    
    self.criticalPoint = [self.mainTableView rectForSection:0].origin.y - self.ceilPointHeight;
    self.criticalOffset = CGPointMake(0, self.criticalPoint);
}

- (void)refreshSegmentedView {
    if ([self shouldLazyLoadListView]) {
        UIView *segmentedView = [self.delegate segmentedViewInPageScrollView:self];
        
        CGRect frame = self.listContainerView.frame;
        frame.origin.y = segmentedView.frame.size.height;
        self.listContainerView.frame = frame;
    }
}

- (void)reloadData {
    self.isLoaded = YES;
    
    for (id<GKPageListViewDelegate> list in self.validListDict.allValues) {
        [list.listView removeFromSuperview];
    }
    [_validListDict removeAllObjects];
    
    // 判断加载方式
    if ([self shouldLazyLoadListView]) {
        [self.listContainerView reloadData];
    }else {
        [self configListViewScroll];
    }
    
    [self.mainTableView reloadData];
    
    self.criticalPoint = [self.mainTableView rectForSection:0].origin.y - self.ceilPointHeight;
    self.criticalOffset = CGPointMake(0, self.criticalPoint);
}

- (void)horizonScrollViewWillBeginScroll {
    self.mainTableView.scrollEnabled = NO;
}

- (void)horizonScrollViewDidEndedScroll {
    self.mainTableView.scrollEnabled = YES;
}

- (void)scrollToOriginalPoint {
    // 这里做了0.01秒的延时，是为了解决一个坑：当通过手势滑动结束调用此方法时，会有可能出现动画结束后UITableView没有回到原点的bug
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isScrollToOriginal) return;
        
        self.isScrollToOriginal  = YES;
        self.isCeilPoint         = NO;
        
        self.isMainCanScroll     = YES;
        self.isListCanScroll     = NO;
        
        [self.mainTableView setContentOffset:CGPointZero animated:YES];
    });
}

- (void)scrollToCriticalPoint {
    if (self.isScrollToCritical) return;
    
    self.isScrollToCritical = YES;
    
    [self.mainTableView setContentOffset:self.criticalOffset animated:YES];
    
    self.isMainCanScroll = NO;
    self.isListCanScroll = YES;
    
    [self mainTableViewCanScrollUpdate];
}

#pragma mark - Private Methods
- (void)configListViewScroll {
    [[self.delegate listViewsInPageScrollView:self] enumerateObjectsUsingBlock:^(id<GKPageListViewDelegate>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        __weak typeof(self) weakSelf = self;
        [obj listViewDidScrollCallback:^(UIScrollView * _Nonnull scrollView) {
            [weakSelf listScrollViewDidScroll:scrollView];
        }];
    }];
}

- (void)listScrollViewDidScroll:(UIScrollView *)scrollView {
    self.currentListScrollView = scrollView;
    
    if (self.isMainScrollDisabled) return;
    
    if (self.isScrollToOriginal || self.isScrollToCritical) return;
    
    // 获取listScrollview偏移量
    CGFloat offsetY = scrollView.contentOffset.y;
    
    // listScrollView下滑至offsetY小于0，禁止其滑动，让mainTableView可下滑
    if (offsetY <= 0) {
        if (self.isDisableMainScrollInCeil) {
            if (self.isAllowListRefresh && offsetY < 0 && self.isCeilPoint) {
                self.isMainCanScroll = NO;
                self.isListCanScroll = YES;
            }else {
                self.isMainCanScroll = YES;
                self.isListCanScroll = NO;
                
                [self setScrollView:scrollView offset:CGPointZero];
                if (self.isControlVerticalIndicator) {
                    scrollView.showsVerticalScrollIndicator = NO;
                }
            }
        }else {
            if (self.isAllowListRefresh && offsetY < 0 && self.mainTableView.contentOffset.y == 0) {
                self.isMainCanScroll = NO;
                self.isListCanScroll = YES;
            }else {
                self.isMainCanScroll = YES;
                self.isListCanScroll = NO;

                if (scrollView.isDecelerating) return;
                [self setScrollView:scrollView offset:CGPointZero];
                if (self.isControlVerticalIndicator) {
                    scrollView.showsVerticalScrollIndicator = NO;
                }
            }
        }
    }else {
        if (self.isListCanScroll) {
            if (self.isControlVerticalIndicator) {
                scrollView.showsVerticalScrollIndicator = YES;
            }
            
            CGFloat headerHeight = self.headerHeight;
            
            if (floor(headerHeight) == 0) {
                [self setScrollView:self.mainTableView offset:self.criticalOffset];
            }else {
                // 如果此时mianTableView并没有滑动，则禁止listView滑动
                if (self.mainTableView.contentOffset.y == 0 && floor(headerHeight) != 0) {
                    self.isMainCanScroll = YES;
                    self.isListCanScroll = NO;

                    if (scrollView.isDecelerating) return;
                    [self setScrollView:scrollView offset:CGPointZero];
                    if (self.isControlVerticalIndicator) {
                        scrollView.showsVerticalScrollIndicator = NO;
                    }
                }else { // 矫正mainTableView的位置
                    [self setScrollView:self.mainTableView offset:self.criticalOffset];
                }
            }
        }else {
            if (scrollView.isDecelerating) return;
            [self setScrollView:scrollView offset:CGPointZero];
        }
    }
}

- (void)mainScrollViewDidScroll:(UIScrollView *)scrollView {
    if (!self.isBeginDragging) {
        // 点击状态栏滑动
        [self listScrollViewOffsetFixed];
        
        [self mainTableViewCanScrollUpdate];
        
        return;
    }
    // 获取mainScrollview偏移量
    CGFloat offsetY = scrollView.contentOffset.y;
    
    if (self.isScrollToOriginal || self.isScrollToCritical) return;
    
    // 根据偏移量判断是否上滑到临界点
    if (offsetY >= self.criticalPoint) {
        self.isCriticalPoint = YES;
    }else {
        self.isCriticalPoint = NO;
    }
    
    // 无偏差临界点，对float值取整判断
    if (!self.isCeilPoint ) {
        if (floor(offsetY) == floor(self.criticalPoint)) {
            self.isCeilPoint = YES;
        }
    }
    
    if (self.isCriticalPoint) {
        // 上滑到临界点后，固定其位置
        [self setScrollView:scrollView offset:self.criticalOffset];
        self.isMainCanScroll = NO;
        self.isListCanScroll = YES;
    }else {
        // 当滑动到无偏差临界点且不允许mainScrollView滑动时做处理
        if (self.isCeilPoint && self.isDisableMainScrollInCeil) {
            self.isMainCanScroll = NO;
            self.isListCanScroll = YES;
            [self setScrollView:scrollView offset:self.criticalOffset];
        }else {
            if (self.isDisableMainScrollInCeil) {
                if (self.isMainCanScroll) {
                    // 未达到临界点，mainScrollview可滑动，需要重置所有listScrollView的位置
                    [self listScrollViewOffsetFixed];
                }else {
                    // 未到达临界点，mainScrollView不可滑动，固定mainScrollView的位置
                    [self mainScrollViewOffsetFixed];
                }
            }else {
                // 如果允许列表刷新，并且mainTableView的offsetY小于0 或者 当前列表的offsetY小于0,mainScrollView不可滑动
                if (self.isAllowListRefresh && ((offsetY <= 0 && self.isMainCanScroll) || (self.currentListScrollView.contentOffset.y < 0 && self.isListCanScroll))) {
                    [self setScrollView:scrollView offset:CGPointZero];
                }else {
                    if (self.isMainCanScroll) {
                        // 未达到临界点，mainScrollview可滑动，需要重置所有listScrollView的位置
                        [self listScrollViewOffsetFixed];
                    }else {
                        // 未到达临界点，mainScrollView不可滑动，固定mainScrollView的位置
                        [self mainScrollViewOffsetFixed];
                    }
                }
            }
        }
    }
    
    [self mainTableViewCanScrollUpdate];
}

// 修正mainTableView的位置
- (void)mainScrollViewOffsetFixed {
    if ([self shouldLazyLoadListView]) {
        for (id<GKPageListViewDelegate> listItem in self.validListDict.allValues) {
            UIScrollView *listScrollView = [listItem listScrollView];
            if (listScrollView.contentOffset.y != 0) {
                [self setScrollView:self.mainTableView offset:self.criticalOffset];
            }
        }
    }else {
        [[self.delegate listViewsInPageScrollView:self] enumerateObjectsUsingBlock:^(id<GKPageListViewDelegate>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            UIScrollView *listScrollView = [obj listScrollView];
            if (listScrollView.contentOffset.y != 0) {
                [self setScrollView:self.mainTableView offset:self.criticalOffset];
            }
        }];
    }
}

// 修正listScrollView的位置
- (void)listScrollViewOffsetFixed {
    if ([self shouldLazyLoadListView]) {
        for (id<GKPageListViewDelegate> listItem in self.validListDict.allValues) {
            UIScrollView *listScrollView = [listItem listScrollView];
            [self setScrollView:listScrollView offset:CGPointZero];
            if (self.isControlVerticalIndicator) {
                listScrollView.showsVerticalScrollIndicator = NO;
            }
        }
    }else {
        [[self.delegate listViewsInPageScrollView:self] enumerateObjectsUsingBlock:^(id<GKPageListViewDelegate>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            UIScrollView *listScrollView = [obj listScrollView];
            [self setScrollView:listScrollView offset:CGPointZero];
            if (self.isControlVerticalIndicator) {
                listScrollView.showsVerticalScrollIndicator = NO;
            }
        }];
    }
}

- (void)mainTableViewCanScrollUpdate {
    if ([self.delegate respondsToSelector:@selector(mainTableViewDidScroll:isMainCanScroll:)]) {
        [self.delegate mainTableViewDidScroll:self.mainTableView isMainCanScroll:self.isMainCanScroll];
    }
}

- (BOOL)shouldLazyLoadListView {
    if ([self.delegate respondsToSelector:@selector(shouldLazyLoadListInPageScrollView:)]) {
        return [self.delegate shouldLazyLoadListInPageScrollView:self];
    }else {
        return _lazyLoadList;
    }
}

- (void)setScrollView:(UIScrollView *)scrollView offset:(CGPoint)offset {
    if (!CGPointEqualToPoint(scrollView.contentOffset, offset)) {
        scrollView.contentOffset = offset;
    }
}

#pragma mark - UITableViewDataSource & UITableViewDelegate
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.isLoaded ? 1 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width  = self.frame.size.width == 0 ? GKPAGE_SCREEN_WIDTH : self.frame.size.width;
    CGFloat height = self.frame.size.height == 0 ? GKPAGE_SCREEN_HEIGHT : self.frame.size.height;
    UIView *pageView = nil;
    if ([self shouldLazyLoadListView]) {
        pageView = [UIView new];
        
        UIView *segmentedView = [self.delegate segmentedViewInPageScrollView:self];
        
        CGFloat x = 0;
        CGFloat y = segmentedView.frame.size.height;
        CGFloat w = width;
        CGFloat h = height - y;
        h -= (self.isMainScrollDisabled ? self.headerHeight : self.ceilPointHeight);
        self.listContainerView.frame = CGRectMake(x, y, w, h);
        [pageView addSubview:segmentedView];
        [pageView addSubview:self.listContainerView];
    }else {
        pageView = [self.delegate pageViewInPageScrollView:self];
    }
    height -= (self.isMainScrollDisabled ? self.headerHeight : self.ceilPointHeight);
    pageView.frame = CGRectMake(0, 0, width, height);
    [cell.contentView addSubview:pageView];
    if ([self.delegate respondsToSelector:@selector(pageScrollViewReloadCell:)]) {
        [self.delegate pageScrollViewReloadCell:self];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat height = self.frame.size.height == 0 ? GKPAGE_SCREEN_HEIGHT : self.frame.size.height;
    height -= (self.isMainScrollDisabled ? self.headerHeight : self.ceilPointHeight);
    return height;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

#pragma mark - GKPageListContainerViewDelegate
- (NSInteger)numberOfRowsInListContainerView:(GKPageListContainerView *)listContainerView {
    return [self.delegate numberOfListsInPageScrollView:self];
}

- (UIView *)listContainerView:(GKPageListContainerView *)listContainerView listViewInRow:(NSInteger)row {
    id<GKPageListViewDelegate> list = self.validListDict[@(row)];
    if (list == nil) {
        list = [self.delegate pageScrollView:self initListAtIndex:row];
        __weak typeof(self) weakSelf = self;
        [list listViewDidScrollCallback:^(UIScrollView *scrollView) {
            [weakSelf listScrollViewDidScroll:scrollView];
        }];
        _validListDict[@(row)] = list;
    }
    return [list listView];
}

#pragma mark - UIScrollViewDelegate
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.isBeginDragging = YES;
    
    if (self.isScrollToOriginal) {
        self.isScrollToOriginal = NO;
        self.isCeilPoint = NO;
    }
    
    if (self.isScrollToCritical) {
        self.isScrollToCritical = NO;
        self.isCeilPoint = YES;
    }
    
    if ([self.delegate respondsToSelector:@selector(mainTableViewWillBeginDragging:)]) {
        [self.delegate mainTableViewWillBeginDragging:scrollView];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self mainScrollViewDidScroll:scrollView];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        self.isBeginDragging = NO;
    }
    if ([self.delegate respondsToSelector:@selector(mainTableViewDidEndDragging:willDecelerate:)]) {
        [self.delegate mainTableViewDidEndDragging:scrollView willDecelerate:decelerate];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    self.isBeginDragging = NO;
    if ([self.delegate respondsToSelector:@selector(mainTableViewDidEndDecelerating:)]) {
        [self.delegate mainTableViewDidEndDecelerating:scrollView];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if ([self.delegate respondsToSelector:@selector(mainTableViewDidEndScrollingAnimation:)]) {
        [self.delegate mainTableViewDidEndScrollingAnimation:scrollView];
    }
    
    if (self.isScrollToOriginal) {
        self.isScrollToOriginal = NO;
        self.isCeilPoint = NO;
        
        // 修正listView偏移
        [self listScrollViewOffsetFixed];
    }

    if (self.isScrollToCritical) {
        self.isScrollToCritical = NO;
        self.isCeilPoint = YES;
    }

    [self mainTableViewCanScrollUpdate];
}

#pragma mark - 懒加载
- (GKPageListContainerView *)listContainerView {
    if (!_listContainerView) {
        _listContainerView = [[GKPageListContainerView alloc] initWithDelegate:self];
    }
    return _listContainerView;
}

@end
