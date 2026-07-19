#import "ViewController.h"

#import "StudentCard.h"
#import "StudentCardReader.h"
#import "BackendResult.h"
#import "CardBackupCodec.h"
#import "CardStore.h"
#import "NFCFSessionController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <notify.h>

@interface ViewController () <UITableViewDataSource, UITableViewDelegate,
                              UIDocumentPickerDelegate>

@property(nonatomic, strong) NFCFSessionController *sessionController;
@property(nonatomic, strong) CardStore *cardStore;
@property(nonatomic, strong) UILabel *statusValue;
@property(nonatomic, strong) UILabel *selectedValue;
@property(nonatomic, strong) UILabel *verificationValue;
@property(nonatomic, strong) UITableView *cardTable;
@property(nonatomic, strong) UIButton *startButton;
@property(nonatomic, strong) UIButton *stopButton;
@property(nonatomic, strong) UIButton *readButton;
@property(nonatomic, strong) UITextView *outputView;
@property(nonatomic, strong) StudentCardReader *tagReader;
@property(nonatomic, assign) BOOL commandRunning;
@property(nonatomic, assign) BOOL nfcActive;
@property(nonatomic, assign) int transmitNotificationToken;
@property(nonatomic, assign) BOOL transmitNotificationRegistered;
@property(nonatomic, strong) NSArray<UIButton *> *managementButtons;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"NFC-F学生証";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.sessionController = [[NFCFSessionController alloc] init];
    self.cardStore = [[CardStore alloc] init];

    [self buildInterface];
    [self registerTransmitNotification];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(applicationDidBecomeActive:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self cleanupTemporaryExports];
    [self refreshState];
}

- (void)dealloc {
    if (self.transmitNotificationRegistered)
        notify_cancel(self.transmitNotificationToken);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    if (self.commandRunning) return;
    if (![self beginCommand]) return;
    [self.sessionController refreshRecoveringIfActive:YES
        completion:^(BackendResult *result) {
            [self finishCommandWithResult:result];
        }];
}

- (void)registerTransmitNotification {
    __weak typeof(self) weakSelf = self;
    int result = notify_register_dispatch(
        "org.hoshitsugi.iosnfcfcardemulation.event.transmit",
        &_transmitNotificationToken, dispatch_get_main_queue(),
        ^(__unused int token) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) return;
            UINotificationFeedbackGenerator *feedback =
                [[UINotificationFeedbackGenerator alloc] init];
            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
            self.statusValue.text = @"通信しました";
            self.statusValue.textColor = UIColor.systemGreenColor;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (self.nfcActive) self.statusValue.text = @"待受中";
            });
        });
    self.transmitNotificationRegistered = result == NOTIFY_STATUS_OK;
}

- (UILabel *)heading:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title
                       action:(SEL)action
                        style:(UIButtonConfiguration *)configuration {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    configuration.title = title;
    button.configuration = configuration;
    [button addTarget:self action:action
         forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildInterface {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    UILabel *safety = [[UILabel alloc] init];
    safety.text = @"自分の学生証を読み取り、この端末で使用します。";
    safety.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    safety.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:safety];

    [stack setCustomSpacing:24 afterView:safety];
    [stack addArrangedSubview:[self heading:@"状態"]];
    self.statusValue = [[UILabel alloc] init];
    self.statusValue.text = @"確認中";
    self.statusValue.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    self.statusValue.adjustsFontForContentSizeCategory = YES;
    [stack addArrangedSubview:self.statusValue];

    [stack setCustomSpacing:24 afterView:self.statusValue];
    [stack addArrangedSubview:[self heading:@"学生証"]];

    self.cardTable = [[UITableView alloc]
        initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.cardTable.dataSource = self;
    self.cardTable.delegate = self;
    self.cardTable.scrollEnabled = YES;
    self.cardTable.backgroundColor = UIColor.clearColor;
    [self.cardTable.heightAnchor constraintEqualToConstant:180].active = YES;
    [stack addArrangedSubview:self.cardTable];

    UILabel *cardHelp = [[UILabel alloc] init];
    cardHelp.text = @"タップでカードを選択します。";
    cardHelp.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cardHelp.textColor = UIColor.secondaryLabelColor;
    cardHelp.numberOfLines = 0;
    [stack addArrangedSubview:cardHelp];

    self.readButton = [self buttonWithTitle:@"新しい学生証を読み取る"
                                     action:@selector(readCard)
                                      style:[UIButtonConfiguration borderedButtonConfiguration]];
    [stack addArrangedSubview:self.readButton];

    self.selectedValue = [[UILabel alloc] init];
    self.selectedValue.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.selectedValue.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:self.selectedValue];

    self.verificationValue = [[UILabel alloc] init];
    self.verificationValue.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.verificationValue.textColor = UIColor.secondaryLabelColor;
    self.verificationValue.numberOfLines = 0;
    [stack addArrangedSubview:self.verificationValue];

    [stack setCustomSpacing:24 afterView:self.verificationValue];
    [stack addArrangedSubview:[self heading:@"NFC-F"]];
    UIStackView *actions = [[UIStackView alloc] init];
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 10;
    actions.distribution = UIStackViewDistributionFillEqually;
    self.startButton = [self buttonWithTitle:@"開始"
                                     action:@selector(startNFC)
                                      style:[UIButtonConfiguration filledButtonConfiguration]];
    self.stopButton = [self buttonWithTitle:@"停止"
                                    action:@selector(stopNFC)
                                     style:[UIButtonConfiguration borderedButtonConfiguration]];
    [actions addArrangedSubview:self.startButton];
    [actions addArrangedSubview:self.stopButton];
    [stack addArrangedSubview:actions];

    UILabel *backgroundNote = [[UILabel alloc] init];
    backgroundNote.text = @"アプリを閉じても、停止するまで動作します。";
    backgroundNote.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    backgroundNote.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:backgroundNote];

    [stack setCustomSpacing:24 afterView:backgroundNote];
    [stack addArrangedSubview:[self heading:@"実行結果"]];
    self.outputView = [[UITextView alloc] init];
    self.outputView.editable = NO;
    self.outputView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.outputView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.outputView.layer.cornerRadius = 10;
    self.outputView.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    [self.outputView.heightAnchor constraintGreaterThanOrEqualToConstant:130].active = YES;
    [stack addArrangedSubview:self.outputView];

    [stack setCustomSpacing:24 afterView:self.outputView];
    [stack addArrangedSubview:[self heading:@"データ管理"]];
    NSArray *titles = @[@"バックアップを書き出す", @"バックアップを復元",
                        @"診断ログを共有", @"すべて消去"];
    NSArray *selectors = @[NSStringFromSelector(@selector(exportBackup)),
                           NSStringFromSelector(@selector(importBackup)),
                           NSStringFromSelector(@selector(exportDiagnostics)),
                           NSStringFromSelector(@selector(confirmEraseAll))];
    NSMutableArray *management = [NSMutableArray array];
    for (NSUInteger index = 0; index < titles.count; ++index) {
        UIButtonConfiguration *style = [UIButtonConfiguration borderedButtonConfiguration];
        if (index == titles.count - 1) style.baseForegroundColor = UIColor.systemRedColor;
        UIButton *button = [self buttonWithTitle:titles[index]
            action:NSSelectorFromString(selectors[index]) style:style];
        [stack addArrangedSubview:button];
        [management addObject:button];
    }
    self.managementButtons = management;

    UILayoutGuide *frame = scroll.frameLayoutGuide;
    UILayoutGuide *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [frame.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [frame.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [frame.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [frame.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-40],
    ]];
}

- (void)setControlsEnabled:(BOOL)enabled {
    self.commandRunning = !enabled;
    BOOL canChangeCards = enabled && !self.nfcActive;
    self.cardTable.userInteractionEnabled = canChangeCards;
    self.startButton.enabled = canChangeCards &&
        self.cardStore.selectedCard != nil;
    self.stopButton.enabled = enabled;
    self.readButton.enabled = canChangeCards;
    for (UIButton *button in self.managementButtons)
        button.enabled = canChangeCards;
}

- (BOOL)beginCommand {
    if (self.commandRunning) return NO;
    [self setControlsEnabled:NO];
    self.statusValue.text = @"処理中";
    self.statusValue.textColor = UIColor.labelColor;
    return YES;
}

- (void)finishCommandWithResult:(BackendResult *)result {
    self.outputView.text = result.rawOutput;
    if ([result.routing isEqual:@"active"])
        self.nfcActive = YES;
    else if ([result.routing isEqual:@"inactive"])
        self.nfcActive = NO;
    if (result.isSuccess) {
        self.statusValue.text = self.nfcActive ? @"待受中" : @"停止中";
        self.statusValue.textColor = self.nfcActive
            ? UIColor.systemGreenColor : UIColor.labelColor;
    } else {
        self.statusValue.text = @"処理できません";
        self.statusValue.textColor = UIColor.systemRedColor;
    }
    [self setControlsEnabled:YES];
    [self updateSelectedLabel];
    [self updateProfileVerification:result];
}

- (void)updateSelectedLabel {
    StudentCard *card = self.cardStore.selectedCard;
    if (card != nil) {
        self.selectedValue.text = [NSString stringWithFormat:@"選択中: %@", card.displayName];
    } else {
        self.selectedValue.text = @"選択されていません";
    }
    [self.cardTable reloadData];
}

- (void)updateProfileVerification:(BackendResult *)result {
    StudentCard *card = self.cardStore.selectedCard;
    if (card == nil) {
        self.verificationValue.text = @"照合: 学生証が選択されていません";
        self.verificationValue.textColor = UIColor.secondaryLabelColor;
        return;
    }
    BOOL active = self.nfcActive;
    BOOL matches = result != nil && card.recordFingerprint.length != 0 &&
        [result.recordFingerprint caseInsensitiveCompare:
            card.recordFingerprint] == NSOrderedSame;
    NSString *state = !active ? @"バックエンド停止中" :
        (matches ? @"有効なプロファイルと一致" : @"有効なプロファイルと不一致");
    self.verificationValue.text = [NSString stringWithFormat:@"IDm: %@\n照合: %@",
                                   card.maskedIDm, state];
    self.verificationValue.textColor = active && !matches
        ? UIColor.systemRedColor : (matches ? UIColor.systemGreenColor
                                            : UIColor.secondaryLabelColor);
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applySelection {
    [self updateSelectedLabel];
    [self updateProfileVerification:nil];
    [self setControlsEnabled:!self.commandRunning];
}

#pragma mark - NFC Control

- (void)refreshState {
    if (![self beginCommand]) return;
    [self.sessionController refreshRecoveringIfActive:NO
        completion:^(BackendResult *result) {
            [self finishCommandWithResult:result];
        }];
}

- (void)startNFC {
    StudentCard *card = self.cardStore.selectedCard;
    if (card == nil) {
        [self showMessage:@"カードを選んでください" message:nil];
        return;
    }
    if (![self beginCommand]) return;
    [self.sessionController startWithCard:card
        completion:^(BackendResult *result) {
            [self finishCommandWithResult:result];
            if (!result.isSuccess)
                [self showMessage:@"開始できません" message:result.message.length
                    ? result.message : @"実行結果を確認してください。"];
        }];
}

- (void)stopNFC {
    if (![self beginCommand]) return;
    [self.sessionController stopWithCompletion:^(BackendResult *result) {
        [self finishCommandWithResult:result];
        if (!result.isSuccess)
            [self showMessage:@"停止できません" message:result.message.length
                ? result.message : @"端末を再起動してください。"];
    }];
}

#pragma mark - Data management

- (void)cleanupTemporaryExports {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = NSTemporaryDirectory();
    for (NSString *name in
         [manager contentsOfDirectoryAtPath:directory error:nil] ?: @[]) {
        if ([name hasPrefix:@"IOSDeGakuseisyo-"] &&
            ([name hasSuffix:@".backup.json"] ||
             [name hasSuffix:@".diagnostics.txt"])) {
            [manager removeItemAtPath:
                [directory stringByAppendingPathComponent:name] error:nil];
        }
    }
}

- (NSURL *)temporaryExportURLWithSuffix:(NSString *)suffix {
    NSString *name = [NSString stringWithFormat:@"IOSDeGakuseisyo-%@.%@",
        NSUUID.UUID.UUIDString, suffix];
    return [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:name];
}

- (BOOL)requireInactiveSession {
    if (!self.nfcActive) return YES;
    [self showMessage:@"先にNFC-Fを停止してください"
              message:@"待受中は学生証データを変更できません。"];
    return NO;
}

- (void)shareFileAtURL:(NSURL *)url source:(UIView *)source {
    UIActivityViewController *controller = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    controller.popoverPresentationController.sourceView = source ?: self.view;
    controller.popoverPresentationController.sourceRect = source != nil
        ? source.bounds : self.view.bounds;
    controller.completionWithItemsHandler = ^(__unused UIActivityType activityType,
        __unused BOOL completed, __unused NSArray *items, __unused NSError *error) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    };
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)exportBackup {
    if (![self requireInactiveSession]) return;
    NSError *error = nil;
    NSData *backup = [self.cardStore exportBackup:&error];
    if (backup == nil) {
        [self showMessage:@"書き出せません" message:error.localizedDescription];
        return;
    }
    NSURL *url = [self temporaryExportURLWithSuffix:@"backup.json"];
    if (![backup writeToURL:url
        options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete
        error:&error]) {
        [self showMessage:@"書き出せません" message:error.localizedDescription];
        return;
    }
    [self shareFileAtURL:url source:self.managementButtons.firstObject];
}

- (void)importBackup {
    if (![self requireInactiveSession]) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeJSON, UTTypeData] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (url == nil) return;
    if (![self requireInactiveSession]) return;
    NSError *error = nil;
    NSNumber *fileSize = nil;
    if (![url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:&error] ||
        fileSize.unsignedLongLongValue > [CardBackupCodec maximumBackupSize]) {
        NSString *message = error.localizedDescription ?:
            @"バックアップは1 MB以下である必要があります。";
        [self showMessage:@"復元できません" message:message];
        return;
    }
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (data == nil || ![self.cardStore restoreBackup:data error:&error]) {
        [self showMessage:@"復元できません" message:error.localizedDescription];
        return;
    }
    [self updateSelectedLabel];
    [self updateProfileVerification:nil];
    [self showMessage:@"復元しました" message:@"バックアップのカードを保存しました。"];
}

- (void)exportDiagnostics {
    if (![self beginCommand]) return;
    [self.sessionController loadLogsWithCompletion:^(BackendResult *result) {
        [self setControlsEnabled:YES];
        self.outputView.text = result.rawOutput;
        self.statusValue.text = self.nfcActive ? @"待受中" : @"停止中";
        self.statusValue.textColor = self.nfcActive
            ? UIColor.systemGreenColor : UIColor.labelColor;
        if (!result.isSuccess) {
            [self showMessage:@"共有できません" message:@"診断ログを取得できませんでした。"];
            return;
        }
        NSString *version = NSBundle.mainBundle.infoDictionary[
            @"CFBundleShortVersionString"] ?: @"unknown";
        NSString *header = [NSString stringWithFormat:@"IOSDeGakuseisyo %@\n%@\n",
                            version, [NSDate date]];
        NSData *data = [[header stringByAppendingString:
            self.sessionController.diagnosticLog]
            dataUsingEncoding:NSUTF8StringEncoding];
        NSURL *url = [self temporaryExportURLWithSuffix:@"diagnostics.txt"];
        NSError *error = nil;
        if (![data writeToURL:url
            options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete
            error:&error]) {
            [self showMessage:@"共有できません" message:error.localizedDescription];
            return;
        }
        [self shareFileAtURL:url source:self.managementButtons.count > 2
            ? self.managementButtons[2] : nil];
    }];
}

- (void)confirmEraseAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"すべて消去しますか？"
        message:@"NFC-Fを停止して、保存したすべてのカードを削除します。この操作は取り消せません。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル"
        style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"停止して消去"
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (![self beginCommand]) return;
        [self.sessionController stopWithCompletion:^(BackendResult *result) {
            self.outputView.text = result.rawOutput;
            if (!result.isSuccess) {
                [self setControlsEnabled:YES];
                [self showMessage:@"消去を中止しました" message:@"NFC-Fを停止できませんでした。"];
                return;
            }
            NSError *error = nil;
            if (![self.cardStore eraseAll:&error]) {
                [self setControlsEnabled:YES];
                [self showMessage:@"消去できません" message:error.localizedDescription];
                return;
            }
            self.nfcActive = NO;
            self.statusValue.text = @"停止中";
            [self updateSelectedLabel];
            [self updateProfileVerification:nil];
            [self setControlsEnabled:YES];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Card reading

- (void)readCard {
    if (self.nfcActive) {
        [self showMessage:@"先にNFC-Fを停止してください"
                  message:@"送信中はカードを読み取れません。"];
        return;
    }
    if (self.tagReader != nil) return;
    [self setControlsEnabled:NO];
    self.statusValue.text = @"読み取り中";
    self.tagReader = [[StudentCardReader alloc] init];
    __weak typeof(self) weakSelf = self;
    [self.tagReader startWithCompletion:^(StudentCard *card, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        self.tagReader = nil;
        [self setControlsEnabled:YES];
        if (error != nil) {
            [self showMessage:@"読み取れません" message:error.localizedDescription];
            self.statusValue.text = @"停止中";
            return;
        }
        if (card == nil) {
            self.statusValue.text = @"停止中";
            return;
        }
        NSError *saveError = nil;
        if (![self.cardStore addCardAndSelect:card error:&saveError]) {
            [self showMessage:@"保存できません"
                      message:saveError.localizedDescription];
            self.statusValue.text = @"停止中";
            return;
        }
        [self applySelection];
        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
        self.statusValue.text = @"読み取りました";
        self.statusValue.textColor = UIColor.labelColor;
    }];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (NSInteger)self.cardStore.cards.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"StudentCard";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }
    StudentCard *card = self.cardStore.cards[(NSUInteger)indexPath.row];
    cell.textLabel.text = card.displayName;
    cell.detailTextLabel.text = card.detailText;
    BOOL selected = (NSInteger)indexPath.row == self.cardStore.selectedIndex;
    cell.imageView.image = [UIImage systemImageNamed:
        selected ? @"checkmark.circle.fill" : @"circle"];
    cell.imageView.tintColor = UIColor.systemBlueColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (![self requireInactiveSession]) return;
    NSError *error = nil;
    if (![self.cardStore selectCardAtIndex:(NSUInteger)indexPath.row
                                     error:&error]) {
        [self showMessage:@"選択できません" message:error.localizedDescription];
        return;
    }
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    [self applySelection];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:
    (NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.row >= (NSInteger)self.cardStore.cards.count) return;
    StudentCard *card = self.cardStore.cards[(NSUInteger)indexPath.row];
    [self showMessage:card.displayName message:card.detailText];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (self.cardStore.cards.count <= 1)
        return [UISwipeActionsConfiguration configurationWithActions:@[]];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *deleteAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive title:@"削除"
                           handler:^(__unused UIContextualAction *action,
                                     __unused UIView *source,
                                     void (^completion)(BOOL)) {
        __strong typeof(weakSelf) self = weakSelf;
        if (![self requireInactiveSession]) {
            completion(NO);
            return;
        }
        NSUInteger index = (NSUInteger)indexPath.row;
        NSError *error = nil;
        if (![self.cardStore removeCardAtIndex:index error:&error]) {
            [self showMessage:@"削除できません" message:error.localizedDescription];
            completion(NO);
            return;
        }
        [self applySelection];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

@end
