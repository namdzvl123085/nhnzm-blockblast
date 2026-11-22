// File: NHNZMClient.m (v2.1 - Full Engine: Vision + 3-Piece Beam Solver + ESP + AutoTouch + IL2CPP Resolver)
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <mach/mach_time.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

// Khi giu tay vao gach trong Block Blast, gach thuong noi len tren dau ngon tay khoang 65pt.
// Neu Auto keo bi lech len/xuong, chi can chinh so nay.
static const CGFloat kBlockLiftOffsetY = 65.0;

#pragma mark - 1. Cau truc du lieu & Beam Solver (3 gach / 6 hoan vi)

typedef struct {
    int grid[5][5];
    int rows;
    int cols;
    BOOL valid;
} NHNZMPiece;

typedef struct {
    int pieceIndex;     // 0, 1, 2
    int row;            // 0..7
    int col;            // 0..7
    int linesCleared;
    int scoreGain;
    double evalScore;
    BOOL valid;
} NHNZMMove;

static BOOL canPlace(const int board[8][8], const NHNZMPiece *p, int r, int c) {
    if (!p->valid) return NO;
    for (int i = 0; i < p->rows; i++) {
        for (int j = 0; j < p->cols; j++) {
            if (p->grid[i][j]) {
                int nr = r + i, nc = c + j;
                if (nr < 0 || nr >= 8 || nc < 0 || nc >= 8 || board[nr][nc] != 0) return NO;
            }
        }
    }
    return YES;
}

static void applyPlace(const int inBoard[8][8], int outBoard[8][8], const NHNZMPiece *p, int r, int c, int *outLines, int *outBlocks) {
    memcpy(outBoard, inBoard, sizeof(int) * 64);
    int blocks = 0;
    for (int i = 0; i < p->rows; i++) {
        for (int j = 0; j < p->cols; j++) {
            if (p->grid[i][j]) {
                outBoard[r + i][c + j] = 1;
                blocks++;
            }
        }
    }
    int fullR[8] = {0}, fullC[8] = {0}, lines = 0;
    for (int i = 0; i < 8; i++) {
        BOOL rf = YES, cf = YES;
        for (int j = 0; j < 8; j++) {
            if (outBoard[i][j] == 0) rf = NO;
            if (outBoard[j][i] == 0) cf = NO;
        }
        if (rf) { fullR[i] = 1; lines++; }
        if (cf) { fullC[i] = 1; lines++; }
    }
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            if (fullR[i] || fullC[j]) outBoard[i][j] = 0;
        }
    }
    if (outLines) *outLines = lines;
    if (outBlocks) *outBlocks = blocks;
}

static double evaluateBoard(const int b[8][8], int linesCleared, BOOL comboPriority) {
    int empty = 0, holes = 0, transitions = 0;
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
            if (b[i][j] == 0) {
                empty++;
                BOOL up    = (i == 0 || b[i-1][j]);
                BOOL down  = (i == 7 || b[i+1][j]);
                BOOL left  = (j == 0 || b[i][j-1]);
                BOOL right = (j == 7 || b[i][j+1]);
                if (up && down && left && right) holes++;
            }
            if (j < 7 && b[i][j] != b[i][j+1]) transitions++;
            if (i < 7 && b[i][j] != b[i+1][j]) transitions++;
        }
    }
    double comboBonus = (comboPriority && linesCleared > 0) ? 450.0 : 0.0;
    return (linesCleared * linesCleared * 160.0) + comboBonus + (empty * 4.2) - (holes * 38.0) - (transitions * 2.5);
}

static int topMovesForPiece(const int board[8][8], const NHNZMPiece *p, int pIdx, BOOL comboPriority, NHNZMMove *outMoves, int maxK) {
    int count = 0;
    int sim[8][8];
    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
            if (!canPlace(board, p, r, c)) continue;
            int lines = 0, blocks = 0;
            applyPlace(board, sim, p, r, c, &lines, &blocks);
            double ev = evaluateBoard(sim, lines, comboPriority);
            NHNZMMove m = { pIdx, r, c, lines, blocks * 10 + (lines > 0 ? lines * lines * 100 : 0), ev, YES };

            int pos = count;
            if (count < maxK) count++;
            else if (ev <= outMoves[maxK - 1].evalScore) continue;
            else pos = maxK - 1;

            while (pos > 0 && outMoves[pos - 1].evalScore < ev) {
                outMoves[pos] = outMoves[pos - 1];
                pos--;
            }
            outMoves[pos] = m;
        }
    }
    return count;
}

static double searchSequence(const int board[8][8], const NHNZMPiece pieces[3], BOOL used[3], BOOL comboMode, int depth, NHNZMMove *bestFirstMove) {
    BOOL anyLeft = NO;
    for (int i = 0; i < 3; i++) if (!used[i] && pieces[i].valid) anyLeft = YES;
    if (!anyLeft) return evaluateBoard(board, 0, NO);

    double bestTotal = -1e12;
    NHNZMMove candidates[8];
    int sim[8][8];

    for (int p = 0; p < 3; p++) {
        if (used[p] || !pieces[p].valid) continue;
        int k = topMovesForPiece(board, &pieces[p], p, (depth == 0 && comboMode), candidates, 8);
        for (int i = 0; i < k; i++) {
            int lines = 0, blocks = 0;
            applyPlace(board, sim, &pieces[p], candidates[i].row, candidates[i].col, &lines, &blocks);
            used[p] = YES;
            double future = searchSequence(sim, pieces, used, comboMode, depth + 1, NULL);
            used[p] = NO;

            double total = candidates[i].evalScore * 0.45 + future;
            if (total > bestTotal) {
                bestTotal = total;
                if (depth == 0 && bestFirstMove) {
                    *bestFirstMove = candidates[i];
                }
            }
        }
    }
    return bestTotal;
}

#pragma mark - 2. Vision Scanner (Doc ban co 8x8 & 3 gach tu man hinh game)

typedef struct {
    int board[8][8];
    NHNZMPiece pieces[3];
    CGRect boardRect;
    CGPoint pieceCenters[3];
    BOOL success;
} NHNZMScanResult;

static inline void getRGB(const uint8_t *data, size_t w, size_t h, size_t bpr, int x, int y, int *r, int *g, int *b) {
    if (x < 0) x = 0; if (x >= (int)w) x = (int)w - 1;
    if (y < 0) y = 0; if (y >= (int)h) y = (int)h - 1;
    const uint8_t *px = data + y * bpr + x * 4;
    *r = px[0]; *g = px[1]; *b = px[2];
}

static NHNZMScanResult scanGameWindow(UIWindow *gameWindow, CGRect boardRect, CGRect trayRect) {
    NHNZMScanResult res;
    memset(&res, 0, sizeof(res));
    res.boardRect = boardRect;
    if (!gameWindow) return res;

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:gameWindow.bounds.size format:fmt];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [gameWindow drawViewHierarchyInRect:gameWindow.bounds afterScreenUpdates:NO];
    }];

    CGImageRef cgImg = img.CGImage;
    if (!cgImg) return res;

    size_t width = CGImageGetWidth(cgImg);
    size_t height = CGImageGetHeight(cgImg);
    size_t bpr = CGImageGetBytesPerRow(cgImg);
    CFDataRef rawData = CGDataProviderCopyData(CGImageGetDataProvider(cgImg));
    if (!rawData) return res;
    const uint8_t *bytes = CFDataGetBytePtr(rawData);

    CGFloat cellW = boardRect.size.width / 8.0;
    CGFloat cellH = boardRect.size.height / 8.0;
    int cellR[8][8], cellG[8][8], cellB[8][8];
    int minLum = 999, emptyR = 25, emptyG = 35, emptyB = 65;

    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
            int cx = (int)(boardRect.origin.x + (c + 0.5) * cellW);
            int cy = (int)(boardRect.origin.y + (r + 0.5) * cellH);
            int rr, gg, bb;
            getRGB(bytes, width, height, bpr, cx, cy, &rr, &gg, &bb);
            cellR[r][c] = rr; cellG[r][c] = gg; cellB[r][c] = bb;
            int lum = (rr + gg + bb) / 3;
            if (lum < minLum) {
                minLum = lum; emptyR = rr; emptyG = gg; emptyB = bb;
            }
        }
    }

    for (int r = 0; r < 8; r++) {
        for (int c = 0; c < 8; c++) {
            int dr = abs(cellR[r][c] - emptyR);
            int dg = abs(cellG[r][c] - emptyG);
            int db = abs(cellB[r][c] - emptyB);
            int diff = dr + dg + db;
            res.board[r][c] = (diff > 75) ? 1 : 0;
        }
    }

    int trayBgR, trayBgG, trayBgB;
    getRGB(bytes, width, height, bpr, (int)(trayRect.origin.x + 6), (int)(trayRect.origin.y + 4), &trayBgR, &trayBgG, &trayBgB);

    CGFloat slotW = trayRect.size.width / 3.0;
    CGFloat previewCell = cellW * 0.52;

    for (int s = 0; s < 3; s++) {
        int x0 = (int)(trayRect.origin.x + s * slotW + 6);
        int x1 = (int)(trayRect.origin.x + (s + 1) * slotW - 6);
        int y0 = (int)(trayRect.origin.y + 4);
        int y1 = (int)(CGRectGetMaxY(trayRect) - 4);

        int minX = x1, maxX = x0, minY = y1, maxY = y0, activePx = 0;
        for (int y = y0; y < y1; y += 2) {
            for (int x = x0; x < x1; x += 2) {
                int rr, gg, bb;
                getRGB(bytes, width, height, bpr, x, y, &rr, &gg, &bb);
                int diff = abs(rr - trayBgR) + abs(gg - trayBgG) + abs(bb - trayBgB);
                int maxC = MAX(rr, MAX(gg, bb));
                if (diff > 85 && maxC > 95) {
                    if (x < minX) minX = x; if (x > maxX) maxX = x;
                    if (y < minY) minY = y; if (y > maxY) maxY = y;
                    activePx++;
                }
            }
        }

        if (activePx < 15 || maxX <= minX || maxY <= minY) {
            res.pieces[s].valid = NO;
            continue;
        }

        int pCols = (int)llround((maxX - minX) / previewCell);
        int pRows = (int)llround((maxY - minY) / previewCell);
        pCols = MAX(1, MIN(5, pCols));
        pRows = MAX(1, MIN(5, pRows));

        res.pieces[s].rows = pRows;
        res.pieces[s].cols = pCols;
        res.pieces[s].valid = YES;
        res.pieceCenters[s] = CGPointMake((minX + maxX) / 2.0, (minY + maxY) / 2.0);

        CGFloat stepX = (CGFloat)(maxX - minX) / pCols;
        CGFloat stepY = (CGFloat)(maxY - minY) / pRows;
        int filled = 0;

        for (int r = 0; r < pRows; r++) {
            for (int c = 0; c < pCols; c++) {
                int sx = (int)(minX + (c + 0.5) * stepX);
                int sy = (int)(minY + (r + 0.5) * stepY);
                int rr, gg, bb;
                getRGB(bytes, width, height, bpr, sx, sy, &rr, &gg, &bb);
                int diff = abs(rr - trayBgR) + abs(gg - trayBgG) + abs(bb - trayBgB);
                if (diff > 75) {
                    res.pieces[s].grid[r][c] = 1;
                    filled++;
                }
            }
        }
        if (filled == 0) res.pieces[s].valid = NO;
    }

    CFRelease(rawData);
    res.success = YES;
    return res;
}

#pragma mark - 3. Auto Touch Engine (Gia lap keo tha IOHIDEvent noi bo)

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef IOHIDEventRef (*fn_CreateDigitizerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, uint32_t);
typedef IOHIDEventRef (*fn_CreateDigitizerFingerEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, boolean_t, boolean_t, uint32_t);
typedef void (*fn_AppendEvent)(IOHIDEventRef, IOHIDEventRef, uint32_t);
typedef void (*fn_SetIntVal)(IOHIDEventRef, uint32_t, CFIndex);

static void nhnzm_sendTouch(CGPoint pt, int phase) {
    static fn_CreateDigitizerEvent createParent = NULL;
    static fn_CreateDigitizerFingerEvent createFinger = NULL;
    static fn_AppendEvent appendEvent = NULL;
    static fn_SetIntVal setIntVal = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        createParent = (fn_CreateDigitizerEvent)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        createFinger = (fn_CreateDigitizerFingerEvent)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
        appendEvent  = (fn_AppendEvent)dlsym(RTLD_DEFAULT, "IOHIDEventAppendEvent");
        setIntVal    = (fn_SetIntVal)dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    });
    if (!createParent || !createFinger || !appendEvent) return;

    CGRect bounds = UIScreen.mainScreen.bounds;
    double nx = pt.x / bounds.size.width;
    double ny = pt.y / bounds.size.height;
    uint64_t ts = mach_absolute_time();

    uint32_t eventMask = (phase == 1) ? 4 : 2;
    boolean_t touching = (phase != 2);

    IOHIDEventRef parent = createParent(kCFAllocatorDefault, ts, 3, 0, 0, eventMask, 0, nx, ny, 0, 0, 0, touching, touching, 0);
    IOHIDEventRef child  = createFinger(kCFAllocatorDefault, ts, 1, 2, eventMask, nx, ny, 0, touching ? 1.0 : 0.0, 0, touching, touching, 0);
    if (setIntVal && parent) setIntVal(parent, 0x0B000019, 1);
    if (parent && child) {
        appendEvent(parent, child, 0);
        SEL sel = NSSelectorFromString(@"_enqueueHIDEvent:");
        if ([UIApplication.sharedApplication respondsToSelector:sel]) {
            ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(UIApplication.sharedApplication, sel, parent);
        }
        CFRelease(child);
        CFRelease(parent);
    }
}

static void nhnzm_dragPiece(CGPoint from, CGPoint to, NSTimeInterval duration, dispatch_block_t completion) {
    int steps = MAX(6, (int)(duration * 60.0));
    NSTimeInterval stepTime = duration / steps;
    CGPoint adjustedTo = CGPointMake(to.x, to.y + kBlockLiftOffsetY);

    nhnzm_sendTouch(from, 0);
    for (int i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / (CGFloat)steps;
        CGPoint cur = CGPointMake(from.x + (adjustedTo.x - from.x) * t,
                                  from.y + (adjustedTo.y - from.y) * t);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(stepTime * i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            nhnzm_sendTouch(cur, 1);
            if (i == steps) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    nhnzm_sendTouch(cur, 2);
                    if (completion) completion();
                });
            }
        });
    }
}

#pragma mark - 4. Dynamic Runtime Engine (IL2CPP Auto-Resolver)

typedef void* (*il2cpp_domain_get_t)(void);
typedef void** (*il2cpp_domain_get_assemblies_t)(void*, size_t*);
typedef void* (*il2cpp_assembly_get_image_t)(void*);
typedef size_t (*il2cpp_image_get_class_count_t)(void*);
typedef void* (*il2cpp_image_get_class_t)(void*, size_t);
typedef const char* (*il2cpp_class_get_name_t)(void*);
typedef void* (*il2cpp_class_get_methods_t)(void*, void**);
typedef const char* (*il2cpp_method_get_name_t)(void*);
typedef uint32_t (*il2cpp_method_get_param_count_t)(void*);
typedef void* (*il2cpp_runtime_invoke_t)(void*, void*, void**, void**);

@interface NHNZMRuntimeBridge : NSObject
@property (nonatomic, assign) BOOL il2cppReady;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *resolvedMethods;
@property (nonatomic, copy) NSString *diagnosticReport;
+ (instancetype)shared;
- (void)scanEngine;
- (BOOL)invokeActionKey:(NSString *)key intParam:(int)val hasParam:(BOOL)hasParam;
@end

@implementation NHNZMRuntimeBridge {
    il2cpp_runtime_invoke_t _invoke;
}

+ (instancetype)shared {
    static NHNZMRuntimeBridge *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [NHNZMRuntimeBridge new]; });
    return s;
}

- (void)scanEngine {
    self.resolvedMethods = [NSMutableDictionary dictionary];
    void *handle = dlopen("@rpath/UnityFramework.framework/UnityFramework", RTLD_LAZY);
    if (!handle) handle = RTLD_DEFAULT;

    il2cpp_domain_get_t domGet             = (il2cpp_domain_get_t)dlsym(handle, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies_t getAsms = (il2cpp_domain_get_assemblies_t)dlsym(handle, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image_t getImg     = (il2cpp_assembly_get_image_t)dlsym(handle, "il2cpp_assembly_get_image");
    il2cpp_image_get_class_count_t cntCls  = (il2cpp_image_get_class_count_t)dlsym(handle, "il2cpp_image_get_class_count");
    il2cpp_image_get_class_t getCls        = (il2cpp_image_get_class_t)dlsym(handle, "il2cpp_image_get_class");
    il2cpp_class_get_name_t clsName        = (il2cpp_class_get_name_t)dlsym(handle, "il2cpp_class_get_name");
    il2cpp_class_get_methods_t getMethods  = (il2cpp_class_get_methods_t)dlsym(handle, "il2cpp_class_get_methods");
    il2cpp_method_get_name_t mName         = (il2cpp_method_get_name_t)dlsym(handle, "il2cpp_method_get_name");
    il2cpp_method_get_param_count_t mArgs  = (il2cpp_method_get_param_count_t)dlsym(handle, "il2cpp_method_get_param_count");
    _invoke                                = (il2cpp_runtime_invoke_t)dlsym(handle, "il2cpp_runtime_invoke");

    if (!domGet || !getAsms || !getImg || !cntCls || !getCls || !_invoke) {
        self.il2cppReady = NO;
        self.diagnosticReport = @"Game dung Cocos2d/Native C++ hoac an symbol IL2CPP.";
        return;
    }

    self.il2cppReady = YES;
    NSMutableString *log = [NSMutableString stringWithString:@"[NHNZM IL2CPP SCAN]\n"];
    size_t asmCount = 0;
    void **asms = getAsms(domGet(), &asmCount);

    for (size_t a = 0; a < asmCount; a++) {
        void *img = getImg(asms[a]);
        if (!img) continue;
        size_t clsCount = cntCls(img);
        for (size_t c = 0; c < clsCount; c++) {
            void *klass = getCls(img, c);
            if (!klass) continue;
            const char *cn = clsName(klass);
            if (!cn) continue;
            NSString *cStr = [NSString stringWithUTF8String:cn];
            NSString *lowC = cStr.lowercaseString;

            if (![lowC containsString:@"score"] && ![lowC containsString:@"board"] &&
                ![lowC containsString:@"block"] && ![lowC containsString:@"game"] &&
                ![lowC containsString:@"grid"]  && ![lowC containsString:@"shape"]) continue;

            void *iter = NULL;
            void *method = NULL;
            while ((method = getMethods(klass, &iter)) != NULL) {
                const char *mn = mName(method);
                if (!mn) continue;
                NSString *mStr = [NSString stringWithUTF8String:mn];
                NSString *lowM = mStr.lowercaseString;
                uint32_t argc = mArgs ? mArgs(method) : 0;

                if ([lowM containsString:@"addscore"] && argc == 1)        self.resolvedMethods[@"addScore"] = [NSValue valueWithPointer:method];
                else if ([lowM containsString:@"setscore"] && argc == 1)   self.resolvedMethods[@"setScore"] = [NSValue valueWithPointer:method];
                else if (([lowM containsString:@"clearboard"] || [lowM containsString:@"clearall"] || [lowM containsString:@"cleargrid"]) && argc == 0)
                                                                           self.resolvedMethods[@"clearBoard"] = [NSValue valueWithPointer:method];
                else if (([lowM containsString:@"refresh"] || [lowM containsString:@"spawn"] || [lowM containsString:@"reroll"]) && [lowC containsString:@"block"] && argc == 0)
                                                                           self.resolvedMethods[@"reroll"] = [NSValue valueWithPointer:method];
                else if ([lowM containsString:@"undo"] && argc == 0)       self.resolvedMethods[@"undo"] = [NSValue valueWithPointer:method];
                else if ([lowM containsString:@"revive"] && argc == 0)     self.resolvedMethods[@"revive"] = [NSValue valueWithPointer:method];

                if (log.length < 4000) [log appendFormat:@"%@::%@(%u)\n", cStr, mStr, argc];
            }
        }
    }
    self.diagnosticReport = log;
}

- (BOOL)invokeActionKey:(NSString *)key intParam:(int)val hasParam:(BOOL)hasParam {
    NSValue *ptrVal = self.resolvedMethods[key];
    if (!self.il2cppReady || !ptrVal || !_invoke) return NO;
    void *method = ptrVal.pointerValue;
    void *exc = NULL;
    void *params[1] = { &val };
    _invoke(method, NULL, hasParam ? params : NULL, &exc);
    return (exc == NULL);
}
@end

#pragma mark - 5. Passthrough Window & Giao dien NHNZM CLIENT

@interface NHNZMPassthroughWindow : UIWindow
@property (nonatomic, weak) UIView *menuCard;
@end

@implementation NHNZMPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.menuCard.hidden || !CGRectContainsPoint(self.menuCard.frame, point)) {
        return nil;
    }
    return hit;
}
@end

@interface NHNZMClientOverlay : NSObject
@property (nonatomic, strong) NHNZMPassthroughWindow *overlayWindow;
@property (nonatomic, weak) UIWindow *gameWindow;
@property (nonatomic, strong) UIView *espContainer;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *autoSolverBtn;
@property (nonatomic, strong) UIButton *modeBtn;
@property (nonatomic, strong) UIButton *espBtn;
@property (nonatomic, strong) UIButton *comboBtn;
@property (nonatomic, strong) UIButton *saveLossBtn;
@property (nonatomic, strong) NSArray<UIButton *> *targetButtons;
@property (nonatomic, strong) NSArray<UIButton *> *speedButtons;

@property (nonatomic, assign) CGRect boardRect;
@property (nonatomic, assign) CGRect trayRect;
@property (nonatomic, assign) BOOL autoSolverOn;
@property (nonatomic, assign) BOOL espOn;
@property (nonatomic, assign) BOOL comboOn;
@property (nonatomic, assign) BOOL saveLossOn;
@property (nonatomic, assign) BOOL isClassicMode;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) NSInteger selectedTargetScore;
@property (nonatomic, assign) NSInteger selectedSpeedIdx;
@property (nonatomic, assign) NSInteger virtualScore;
@property (nonatomic, strong) NSTimer *loopTimer;
@end

@implementation NHNZMClientOverlay

+ (instancetype)shared {
    static NHNZMClientOverlay *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [NHNZMClientOverlay new]; });
    return instance;
}

- (UIColor *)hex:(NSUInteger)rgb {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF)/255.0
                           green:((rgb >> 8) & 0xFF)/255.0
                            blue:(rgb & 0xFF)/255.0 alpha:1.0];
}

- (UIButton *)makeBtn:(NSString *)title bg:(UIColor *)bg radius:(CGFloat)r fontSize:(CGFloat)fs action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:fs];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.backgroundColor = bg;
    b.layer.cornerRadius = r;
    b.layer.borderWidth = 0.8;
    b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)setup {
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    if (!activeScene) return;

    self.gameWindow = activeScene.windows.firstObject;
    CGRect scr = activeScene.screen.bounds;

    CGFloat bw = scr.size.width * 0.91;
    self.boardRect = CGRectMake((scr.size.width - bw) / 2.0, scr.size.height * 0.235, bw, bw);
    self.trayRect  = CGRectMake(scr.size.width * 0.04, CGRectGetMaxY(self.boardRect) + 24.0, scr.size.width * 0.92, scr.size.height * 0.165);

    self.isClassicMode = YES;
    self.saveLossOn = YES;
    self.espOn = YES;
    self.comboOn = YES;
    self.selectedTargetScore = 0;
    self.selectedSpeedIdx = 1;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NHNZMRuntimeBridge shared] scanEngine];
    });

    self.overlayWindow = [[NHNZMPassthroughWindow alloc] initWithWindowScene:activeScene];
    self.overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    self.overlayWindow.backgroundColor = UIColor.clearColor;
    self.overlayWindow.rootViewController = [UIViewController new];
    self.overlayWindow.rootViewController.view.backgroundColor = UIColor.clearColor;

    self.espContainer = [[UIView alloc] initWithFrame:scr];
    self.espContainer.userInteractionEnabled = NO;
    self.espContainer.backgroundColor = UIColor.clearColor;
    [self.overlayWindow.rootViewController.view addSubview:self.espContainer];

    CGFloat cardW = MIN(scr.size.width - 20, 380);
    CGFloat cardH = 385;
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake((scr.size.width - cardW)/2.0, 52, cardW, cardH)];
    self.menuView.backgroundColor = [[self hex:0x0E1525] colorWithAlphaComponent:0.95];
    self.menuView.layer.cornerRadius = 18;
    self.menuView.layer.borderWidth = 1.2;
    self.menuView.layer.borderColor = [self hex:0x233554].CGColor;
    self.menuView.clipsToBounds = YES;

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.menuView addGestureRecognizer:pan];

    UITapGestureRecognizer *threeFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    threeFingerTap.numberOfTouchesRequired = 3;
    [self.gameWindow addGestureRecognizer:threeFingerTap];

    UITapGestureRecognizer *topTripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTopEdgeTripleTap:)];
    topTripleTap.numberOfTapsRequired = 3;
    [self.gameWindow addGestureRecognizer:topTripleTap];

    [self buildUI:cardW];

    [self.overlayWindow.rootViewController.view addSubview:self.menuView];
    self.overlayWindow.menuCard = self.menuView;
    self.overlayWindow.hidden = NO;

    [self restartLoopTimer];
}

- (void)buildUI:(CGFloat)w {
    CGFloat pad = 12, innerW = w - pad * 2, y = 12;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, innerW - 95, 28)];
    title.text = @"🧩 NHNZM CLIENT";
    title.textColor = [self hex:0x29D9F9];
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.menuView addSubview:title];

    UIButton *hideBtn = [self makeBtn:@"Ẩn (3-Tap)" bg:[self hex:0x232B3E] radius:10 fontSize:12 action:@selector(toggleMenu)];
    hideBtn.frame = CGRectMake(w - pad - 88, y, 88, 28);
    [self.menuView addSubview:hideBtn];
    y += 34;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, innerW, 20)];
    self.statusLabel.text = @"🎯 NHNZM CLIENT • Đang theo dõi bàn cờ 8x8...";
    self.statusLabel.textColor = [self hex:0xB8C7E0];
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightSemibold];
    [self.menuView addSubview:self.statusLabel];
    y += 28;

    CGFloat halfW = (innerW - 8) / 2.0;
    self.autoSolverBtn = [self makeBtn:@"▶ AUTO SOLVER: TẮT" bg:[self hex:0x108A52] radius:10 fontSize:13 action:@selector(toggleAutoSolver)];
    self.autoSolverBtn.frame = CGRectMake(pad, y, halfW, 40);
    [self.menuView addSubview:self.autoSolverBtn];

    self.modeBtn = [self makeBtn:@"🎮 MODE: CLASSIC" bg:[self hex:0x1E60D5] radius:10 fontSize:13 action:@selector(toggleMode)];
    self.modeBtn.frame = CGRectMake(pad + halfW + 8, y, halfW, 40);
    [self.menuView addSubview:self.modeBtn];
    y += 48;

    UILabel *targetLbl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, innerW, 18)];
    targetLbl.text = @"🎯 MỨC ĐIỂM MỤC TIÊU (CHỌN ĐỂ TỰ DỪNG / ĐẶT ĐIỂM):";
    targetLbl.textColor = [self hex:0x94A3B8];
    targetLbl.font = [UIFont boldSystemFontOfSize:10.5];
    [self.menuView addSubview:targetLbl];
    y += 22;

    NSArray *targets = @[@"10K", @"50K", @"100K", @"500K", @"1M", @"∞"];
    NSMutableArray *tBtns = [NSMutableArray array];
    CGFloat pillW = (innerW - 5 * 6) / 6.0;
    for (int i = 0; i < 6; i++) {
        UIColor *bg = (i == 5) ? [self hex:0x1E9CE6] : [self hex:0x1E2636];
        UIButton *b = [self makeBtn:targets[i] bg:bg radius:9 fontSize:12 action:@selector(selectTarget:)];
        b.tag = i;
        b.frame = CGRectMake(pad + i * (pillW + 6), y, pillW, 32);
        [self.menuView addSubview:b];
        [tBtns addObject:b];
    }
    self.targetButtons = tBtns;
    y += 40;

    CGFloat thirdW = (innerW - 12) / 3.0;
    UIButton *setScoreBtn = [self makeBtn:@"💎 Đặt Điểm Này" bg:[self hex:0x7B2CBF] radius:10 fontSize:12 action:@selector(actionSetScore)];
    setScoreBtn.frame = CGRectMake(pad, y, thirdW, 38);
    [self.menuView addSubview:setScoreBtn];

    UIButton *add25kBtn = [self makeBtn:@"⚡ +25K Điểm" bg:[self hex:0xD97706] radius:10 fontSize:12 action:@selector(actionAdd25K)];
    add25kBtn.frame = CGRectMake(pad + thirdW + 6, y, thirdW, 38);
    [self.menuView addSubview:add25kBtn];

    UIButton *solve1Btn = [self makeBtn:@"🎯 Giải 1 Nước" bg:[self hex:0x0284C7] radius:10 fontSize:12 action:@selector(actionSolveOnce)];
    solve1Btn.frame = CGRectMake(pad + (thirdW + 6) * 2, y, thirdW, 38);
    [self.menuView addSubview:solve1Btn];
    y += 46;

    UILabel *spdLbl = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, 64, 32)];
    spdLbl.text = @"TỐC ĐỘ:";
    spdLbl.textColor = UIColor.whiteColor;
    spdLbl.font = [UIFont boldSystemFontOfSize:12];
    [self.menuView addSubview:spdLbl];

    NSArray *speeds = @[@"1x", @"2x", @"5x", @"⚡ Turbo"];
    NSMutableArray *sBtns = [NSMutableArray array];
    CGFloat spdW = (innerW - 68 - 18) / 4.0;
    for (int i = 0; i < 4; i++) {
        UIColor *bg = (i == 1) ? [self hex:0xEA580C] : [self hex:0x1E2636];
        UIButton *b = [self makeBtn:speeds[i] bg:bg radius:9 fontSize:12 action:@selector(selectSpeed:)];
        b.tag = i;
        b.frame = CGRectMake(pad + 68 + i * (spdW + 6), y, spdW, 32);
        [self.menuView addSubview:b];
        [sBtns addObject:b];
    }
    self.speedButtons = sBtns;
    y += 40;

    UIButton *clearBtn = [self makeBtn:@"💣 Nổ Bàn Cờ" bg:[self hex:0xDC2626] radius:10 fontSize:12 action:@selector(actionClearBoard)];
    clearBtn.frame = CGRectMake(pad, y, thirdW, 38);
    [self.menuView addSubview:clearBtn];

    UIButton *rerollBtn = [self makeBtn:@"🔄 Đổi 3 Gạch" bg:[self hex:0x1D4ED8] radius:10 fontSize:12 action:@selector(actionRerollPieces)];
    rerollBtn.frame = CGRectMake(pad + thirdW + 6, y, thirdW, 38);
    [self.menuView addSubview:rerollBtn];

    UIButton *undoBtn = [self makeBtn:@"↩ Hoàn Tác" bg:[self hex:0x334155] radius:10 fontSize:12 action:@selector(actionUndo)];
    undoBtn.frame = CGRectMake(pad + (thirdW + 6) * 2, y, thirdW, 38);
    [self.menuView addSubview:undoBtn];
    y += 46;

    self.espBtn = [self makeBtn:@"👁 ESP: BẬT" bg:[self hex:0x15803D] radius:10 fontSize:12 action:@selector(toggleESP)];
    self.espBtn.frame = CGRectMake(pad, y, thirdW, 36);
    [self.menuView addSubview:self.espBtn];

    self.comboBtn = [self makeBtn:@"🔥 Combo: BẬT" bg:[self hex:0xEA580C] radius:10 fontSize:12 action:@selector(toggleCombo)];
    self.comboBtn.frame = CGRectMake(pad + thirdW + 6, y, thirdW, 36);
    [self.menuView addSubview:self.comboBtn];

    self.saveLossBtn = [self makeBtn:@"🛡 Cứu Thua: BẬT" bg:[self hex:0x15803D] radius:10 fontSize:12 action:@selector(toggleSaveLoss)];
    self.saveLossBtn.frame = CGRectMake(pad + (thirdW + 6) * 2, y, thirdW, 36);
    [self.menuView addSubview:self.saveLossBtn];
    y += 42;

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, innerW, 30)];
    tip.text = @"💡 Mẹo: Chạm 3 ngón hoặc 3 lần mép trên để ẨN / HIỆN • NHNZM CLIENT";
    tip.textColor = [self hex:0x94A3B8];
    tip.font = [UIFont systemFontOfSize:10.5];
    tip.numberOfLines = 2;
    [self.menuView addSubview:tip];
}

#pragma mark - 6. Ve ESP & Vong lap Auto Solver

- (void)clearESP {
    for (CALayer *l in [self.espContainer.layer.sublayers copy]) [l removeFromSuperlayer];
}

- (void)drawESPForMove:(NHNZMMove)move scan:(NHNZMScanResult)scan {
    [self clearESP];
    if (!self.espOn || !move.valid) return;

    CGFloat cellW = self.boardRect.size.width / 8.0;
    CGFloat cellH = self.boardRect.size.height / 8.0;

    CAShapeLayer *frameLayer = [CAShapeLayer layer];
    frameLayer.path = [UIBezierPath bezierPathWithRect:self.boardRect].CGPath;
    frameLayer.strokeColor = [[self hex:0x29D9F9] colorWithAlphaComponent:0.35].CGColor;
    frameLayer.fillColor = UIColor.clearColor.CGColor;
    frameLayer.lineWidth = 1.2;
    [self.espContainer.layer addSublayer:frameLayer];

    NHNZMPiece p = scan.pieces[move.pieceIndex];
    UIBezierPath *cellsPath = [UIBezierPath bezierPath];
    CGFloat sumX = 0, sumY = 0; int cnt = 0;

    for (int i = 0; i < p.rows; i++) {
        for (int j = 0; j < p.cols; j++) {
            if (!p.grid[i][j]) continue;
            CGRect r = CGRectMake(self.boardRect.origin.x + (move.col + j) * cellW + 2,
                                  self.boardRect.origin.y + (move.row + i) * cellH + 2,
                                  cellW - 4, cellH - 4);
            [cellsPath appendPath:[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:6]];
            sumX += CGRectGetMidX(r); sumY += CGRectGetMidY(r); cnt++;
        }
    }

    CAShapeLayer *targetLayer = [CAShapeLayer layer];
    targetLayer.path = cellsPath.CGPath;
    targetLayer.fillColor = [[self hex:0x29D9F9] colorWithAlphaComponent:0.32].CGColor;
    targetLayer.strokeColor = [self hex:0x29D9F9].CGColor;
    targetLayer.lineWidth = 2.5;
    [self.espContainer.layer addSublayer:targetLayer];

    CGPoint startPt = scan.pieceCenters[move.pieceIndex];
    CGPoint endPt = (cnt > 0) ? CGPointMake(sumX / cnt, sumY / cnt) : startPt;

    CAShapeLayer *srcRing = [CAShapeLayer layer];
    srcRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(startPt.x - 24, startPt.y - 24, 48, 48)].CGPath;
    srcRing.fillColor = [[self hex:0xF43F5E] colorWithAlphaComponent:0.25].CGColor;
    srcRing.strokeColor = [self hex:0xF43F5E].CGColor;
    srcRing.lineWidth = 2.5;
    [self.espContainer.layer addSublayer:srcRing];

    UIBezierPath *arrowPath = [UIBezierPath bezierPath];
    [arrowPath moveToPoint:startPt];
    [arrowPath addLineToPoint:endPt];

    CAShapeLayer *arrow = [CAShapeLayer layer];
    arrow.path = arrowPath.CGPath;
    arrow.strokeColor = [self hex:0x38BDF8].CGColor;
    arrow.lineWidth = 2.5;
    arrow.lineDashPattern = @[@6, @4];
    [self.espContainer.layer addSublayer:arrow];
}

- (void)restartLoopTimer {
    [self.loopTimer invalidate];
    NSTimeInterval intervals[] = { 1.15, 0.72, 0.40, 0.22 };
    NSTimeInterval dt = self.autoSolverOn ? intervals[self.selectedSpeedIdx] : 0.65;
    self.loopTimer = [NSTimer scheduledTimerWithTimeInterval:dt target:self selector:@selector(tickSolver) userInfo:nil repeats:YES];
}

- (void)tickSolver {
    if (self.isDragging || (!self.autoSolverOn && !self.espOn)) return;
    [self runSolveAndAct:self.autoSolverOn];
}

- (void)runSolveAndAct:(BOOL)executeDrag {
    self.espContainer.hidden = YES;
    NHNZMScanResult scan = scanGameWindow(self.gameWindow, self.boardRect, self.trayRect);
    self.espContainer.hidden = NO;

    if (!scan.success) return;

    BOOL used[3] = { !scan.pieces[0].valid, !scan.pieces[1].valid, !scan.pieces[2].valid };
    NHNZMMove best = { -1, -1, -1, 0, 0, -1e9, NO };
    searchSequence(scan.board, scan.pieces, used, self.comboOn, 0, &best);

    if (!best.valid) {
        [self clearESP];
        if (used[0] && used[1] && used[2]) return;
        self.statusLabel.text = @"⚠️ Hết nước đi! Đang kích hoạt Cứu Thua...";
        if (self.saveLossOn) [self actionRerollPieces];
        return;
    }

    self.statusLabel.text = [NSString stringWithFormat:@"🎯 Gạch #%d -> Ô (%d,%d) • Nổ %d hàng • +%d",
                             best.pieceIndex + 1, best.row + 1, best.col + 1, best.linesCleared, best.scoreGain];

    [self drawESPForMove:best scan:scan];

    if (executeDrag) {
        if (self.selectedTargetScore > 0 && self.virtualScore >= self.selectedTargetScore) {
            self.autoSolverOn = NO;
            [self.autoSolverBtn setTitle:@"▶ AUTO SOLVER: ĐẠT MỤC TIÊU" forState:UIControlStateNormal];
            self.autoSolverBtn.backgroundColor = [self hex:0x108A52];
            [self restartLoopTimer];
            return;
        }

        CGFloat cellW = self.boardRect.size.width / 8.0;
        CGFloat cellH = self.boardRect.size.height / 8.0;
        NHNZMPiece p = scan.pieces[best.pieceIndex];
        CGPoint targetCenter = CGPointMake(
            self.boardRect.origin.x + (best.col + p.cols / 2.0) * cellW,
            self.boardRect.origin.y + (best.row + p.rows / 2.0) * cellH
        );
        CGPoint fromPt = scan.pieceCenters[best.pieceIndex];

        NSTimeInterval dragDurs[] = { 0.42, 0.24, 0.13, 0.08 };
        self.isDragging = YES;
        self.virtualScore += best.scoreGain;
        nhnzm_dragPiece(fromPt, targetCenter, dragDurs[self.selectedSpeedIdx], ^{
            self.isDragging = NO;
        });
    }
}

#pragma mark - 7. Actions (Nut bam Menu)

- (void)handleDrag:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.overlayWindow];
    self.menuView.center = CGPointMake(self.menuView.center.x + t.x, self.menuView.center.y + t.y);
    [pan setTranslation:CGPointZero inView:self.overlayWindow];
}

- (void)handleTopEdgeTripleTap:(UITapGestureRecognizer *)tap {
    if ([tap locationInView:self.overlayWindow].y < 90) [self toggleMenu];
}

- (void)toggleMenu { self.menuView.hidden = !self.menuView.hidden; }

- (void)toggleAutoSolver {
    self.autoSolverOn = !self.autoSolverOn;
    [self.autoSolverBtn setTitle:self.autoSolverOn ? @"⏸ AUTO SOLVER: BẬT" : @"▶ AUTO SOLVER: TẮT" forState:UIControlStateNormal];
    self.autoSolverBtn.backgroundColor = self.autoSolverOn ? [self hex:0xD97706] : [self hex:0x108A52];
    [self restartLoopTimer];
}

- (void)toggleMode {
    self.isClassicMode = !self.isClassicMode;
    [self.modeBtn setTitle:self.isClassicMode ? @"🎮 MODE: CLASSIC" : @"🗺 MODE: ADVENTURE" forState:UIControlStateNormal];
}

- (void)selectTarget:(UIButton *)sender {
    NSInteger vals[] = { 10000, 50000, 100000, 500000, 1000000, 0 };
    self.selectedTargetScore = vals[sender.tag];
    for (UIButton *b in self.targetButtons) b.backgroundColor = (b == sender) ? [self hex:0x1E9CE6] : [self hex:0x1E2636];
}

- (void)selectSpeed:(UIButton *)sender {
    self.selectedSpeedIdx = sender.tag;
    for (UIButton *b in self.speedButtons) b.backgroundColor = (b == sender) ? [self hex:0xEA580C] : [self hex:0x1E2636];
    [self restartLoopTimer];
}

- (void)toggleESP {
    self.espOn = !self.espOn;
    [self.espBtn setTitle:self.espOn ? @"👁 ESP: BẬT" : @"👁 ESP: TẮT" forState:UIControlStateNormal];
    self.espBtn.backgroundColor = self.espOn ? [self hex:0x15803D] : [self hex:0x27303F];
    if (!self.espOn) [self clearESP];
}

- (void)toggleCombo {
    self.comboOn = !self.comboOn;
    [self.comboBtn setTitle:self.comboOn ? @"🔥 Combo: BẬT" : @"🔥 Combo: TẮT" forState:UIControlStateNormal];
    self.comboBtn.backgroundColor = self.comboOn ? [self hex:0xEA580C] : [self hex:0x27303F];
}

- (void)toggleSaveLoss {
    self.saveLossOn = !self.saveLossOn;
    [self.saveLossBtn setTitle:self.saveLossOn ? @"🛡 Cứu Thua: BẬT" : @"🛡 Cứu Thua: TẮT" forState:UIControlStateNormal];
    self.saveLossBtn.backgroundColor = self.saveLossOn ? [self hex:0x15803D] : [self hex:0x27303F];
}

- (void)actionSolveOnce { [self runSolveAndAct:YES]; }

- (void)runMemoryAction:(NSString *)key label:(NSString *)okText param:(int)p hasParam:(BOOL)hp {
    if ([[NHNZMRuntimeBridge shared] invokeActionKey:key intParam:p hasParam:hp]) {
        self.statusLabel.text = okText;
    } else {
        UIPasteboard.generalPasteboard.string = [NHNZMRuntimeBridge shared].diagnosticReport ?: @"No symbols";
        self.statusLabel.text = @"⚠️ Cần map tên hàm cho bản game này (đã copy log)";
    }
}

- (void)actionSetScore     { [self runMemoryAction:@"setScore"   label:@"💎 Đã đặt điểm mục tiêu!" param:(int)(self.selectedTargetScore ?: 999999) hasParam:YES]; }
- (void)actionAdd25K       { [self runMemoryAction:@"addScore"   label:@"⚡ Đã cộng +25,000 điểm!" param:25000 hasParam:YES]; }
- (void)actionClearBoard   { [self runMemoryAction:@"clearBoard" label:@"💣 Đã kích hoạt Nổ Bàn Cờ!" param:0 hasParam:NO]; }
- (void)actionRerollPieces { [self runMemoryAction:@"reroll"     label:@"🔄 Đã đổi 3 viên gạch mới!" param:0 hasParam:NO]; }
- (void)actionUndo         { [self runMemoryAction:@"undo"       label:@"↩ Đã hoàn tác nước đi!" param:0 hasParam:NO]; }

@end

__attribute__((constructor))
static void nhnzm_entry(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[NHNZMClientOverlay shared] setup];
    });
}
