#import "CardStore.h"

#import "StudentCard.h"
#import "CardBackupCodec.h"
#import "StudentCardRepository.h"

static const NSUInteger kMaximumCardCount = 64;

static NSError *StoreError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"org.hoshitsugi.iosdegakuseisyo.store"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface CardStore ()
@property(nonatomic, strong) NSMutableArray<StudentCard *> *mutableCards;
@property(nonatomic, assign, readwrite) NSInteger selectedIndex;
@end

@implementation CardStore

- (instancetype)init {
    self = [super init];
    if (self) {
        NSMutableArray *saved = [StudentCardRepository loadAllCards];
        _mutableCards = saved ?: [NSMutableArray array];
        NSInteger selected = [StudentCardRepository savedSelectedIndex];
        _selectedIndex = selected >= 0 && selected < (NSInteger)_mutableCards.count
            ? selected : (_mutableCards.count != 0 ? 0 : NSNotFound);
        if (_mutableCards.count != 0 && selected != _selectedIndex) {
            (void)[StudentCardRepository saveCards:_mutableCards
                                     selectedIndex:_selectedIndex error:nil];
        }
    }
    return self;
}

- (NSArray<StudentCard *> *)cards {
    return [_mutableCards copy];
}

- (StudentCard *)selectedCard {
    return _selectedIndex >= 0 && _selectedIndex < (NSInteger)_mutableCards.count
        ? _mutableCards[(NSUInteger)_selectedIndex] : nil;
}

- (BOOL)addCardAndSelect:(StudentCard *)card error:(NSError **)error {
    if (card == nil || _mutableCards.count >= kMaximumCardCount) {
        if (error != NULL)
            *error = StoreError(1, @"保存できる学生証は64枚までです。");
        return NO;
    }
    NSInteger previous = _selectedIndex;
    [_mutableCards addObject:card];
    _selectedIndex = (NSInteger)_mutableCards.count - 1;
    if ([self save:error]) return YES;
    [_mutableCards removeLastObject];
    _selectedIndex = previous;
    return NO;
}

- (BOOL)selectCardAtIndex:(NSUInteger)index error:(NSError **)error {
    if (index >= _mutableCards.count) {
        if (error != NULL) *error = StoreError(2, @"学生証が見つかりません。");
        return NO;
    }
    NSInteger previous = _selectedIndex;
    _selectedIndex = (NSInteger)index;
    if ([self save:error]) return YES;
    _selectedIndex = previous;
    return NO;
}

- (BOOL)removeCardAtIndex:(NSUInteger)index error:(NSError **)error {
    if (index >= _mutableCards.count || _mutableCards.count <= 1) {
        if (error != NULL)
            *error = StoreError(3, @"最後の学生証はここでは削除できません。");
        return NO;
    }
    NSMutableArray *previousCards = [_mutableCards mutableCopy];
    NSInteger previousIndex = _selectedIndex;
    [_mutableCards removeObjectAtIndex:index];
    if (_selectedIndex == (NSInteger)index)
        _selectedIndex = 0;
    else if (_selectedIndex > (NSInteger)index)
        --_selectedIndex;
    if ([self save:error]) return YES;
    _mutableCards = previousCards;
    _selectedIndex = previousIndex;
    return NO;
}

- (BOOL)save:(NSError **)error {
    return [StudentCardRepository saveCards:_mutableCards
                              selectedIndex:_selectedIndex error:error];
}

- (NSData *)exportBackup:(NSError **)error {
    NSMutableArray *records = [NSMutableArray arrayWithCapacity:_mutableCards.count];
    for (StudentCard *card in _mutableCards) {
        NSData *data = [card recordData:error];
        if (data == nil) return nil;
        [records addObject:data];
    }
    return [CardBackupCodec encodeRecords:records
                            selectedIndex:_selectedIndex error:error];
}

- (BOOL)restoreBackup:(NSData *)data error:(NSError **)error {
    NSArray<NSData *> *records = nil;
    NSInteger selected = 0;
    if (![CardBackupCodec decodeBackup:data records:&records
                         selectedIndex:&selected error:error]) return NO;
    NSMutableArray *cards = [NSMutableArray arrayWithCapacity:records.count];
    for (NSData *record in records) {
        StudentCard *card = [StudentCard cardWithRecordData:record error:error];
        if (card == nil) return NO;
        [cards addObject:card];
    }
    if (![StudentCardRepository saveCards:cards
                            selectedIndex:selected error:error]) return NO;
    _mutableCards = cards;
    _selectedIndex = selected;
    return YES;
}

- (BOOL)eraseAll:(NSError **)error {
    if (![StudentCardRepository saveCards:@[]
                            selectedIndex:NSNotFound error:error])
        return NO;
    [_mutableCards removeAllObjects];
    _selectedIndex = NSNotFound;
    return [StudentCardRepository deleteStorageKeys:error];
}

@end
