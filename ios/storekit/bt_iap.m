// ios/storekit/bt_iap.m — Båtspillet's StoreKit bridge.
//
// Linked into the LÖVE app binary by ios.sh (plain extra .o + `-framework
// StoreKit` on OTHER_LDFLAGS — the engine project is never modified). The Lua
// side (src/systems/iap.lua) reaches these functions through LuaJIT's FFI, so
// no Lua registration code is needed either.
//
// Exposes a tiny C API around the one thing this game sells (a single
// non-consumable). Poll-based: StoreKit callbacks push short event strings
// onto a queue; Lua drains it once per frame with bt_iap_poll().
//
//   bt_iap_init(productId)  fetch product info (price), attach the observer
//   bt_iap_buy()            start the purchase (fails cleanly if offline)
//   bt_iap_restore()        restore previous purchases
//   bt_iap_poll()           next event or NULL:
//                             "purchased" | "restored" | "restoredone"
//                             "failed:<msg>" | "restorefailed:<msg>"
//   bt_iap_price()          localized display price, or NULL until fetched
//
// StoreKit 1 (SKPaymentQueue) on purpose: it's Objective-C (Swift-free link),
// runs on both iOS and macOS, and is still accepted by App Review. When LÖVE
// or Apple forces the move to StoreKit 2, only this file changes — the C API
// and everything above it stays.
//
// Marked __attribute__((used)) so -dead_strip can't drop the (statically
// unreferenced) functions, and default visibility so LuaJIT's dlsym finds
// them in the executable.

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

#define BT_EXPORT __attribute__((used, visibility("default")))

// ── Haptics ──────────────────────────────────────────────────────────────────
// A crisp Taptic tap for button feedback (kind 0 = light press-in, 1 = medium
// "it fired"). iPhone-only hardware; on iPads and in the simulator the
// generator simply no-ops, so callers never need to care.
BT_EXPORT void bt_haptic(int kind) {
#if TARGET_OS_IOS
    static UIImpactFeedbackGenerator *light = nil, *medium = nil;
    if (!light) {
        light  = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        medium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    }
    UIImpactFeedbackGenerator *g = (kind >= 1) ? medium : light;
    [g prepare];
    [g impactOccurred];
#endif
}

static NSMutableArray<NSString *> *bt_events;
static NSString *bt_priceStr = nil;
static SKProduct *bt_product = nil;
static NSString *bt_productId = nil;

static void bt_push(NSString *ev) {
    // StoreKit delivers on the main thread (observer added there) and Lua
    // polls from the main thread, so a plain array is safe.
    [bt_events addObject:ev];
}

@interface BTStore : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@end

static BTStore *bt_store = nil;
static SKProductsRequest *bt_request = nil;

@implementation BTStore

- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (response.products.count > 0) {
            bt_product = response.products.firstObject;
            NSNumberFormatter *f = [NSNumberFormatter new];
            f.numberStyle = NSNumberFormatterCurrencyStyle;
            f.locale = bt_product.priceLocale;
            bt_priceStr = [f stringFromNumber:bt_product.price];
            NSLog(@"[bt_iap] product ready: %@ (%@)", bt_product.productIdentifier, bt_priceStr);
        } else {
            NSLog(@"[bt_iap] product not found: %@", bt_productId);
        }
        bt_request = nil;
    });
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[bt_iap] product fetch failed: %@", error.localizedDescription);
        bt_request = nil;
    });
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *t in transactions) {
        switch (t.transactionState) {
        case SKPaymentTransactionStatePurchased:
            bt_push(@"purchased");
            [queue finishTransaction:t];
            break;
        case SKPaymentTransactionStateRestored:
            bt_push(@"restored");
            [queue finishTransaction:t];
            break;
        case SKPaymentTransactionStateFailed:
            bt_push([NSString stringWithFormat:@"failed:%@",
                     t.error.localizedDescription ?: @""]);
            [queue finishTransaction:t];
            break;
        default:   // Purchasing / Deferred ("ask to buy"): nothing to do yet
            break;
        }
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    bt_push(@"restoredone");   // Lua: success iff a "restored" arrived before this
}

- (void)paymentQueue:(SKPaymentQueue *)queue
    restoreCompletedTransactionsFailedWithError:(NSError *)error {
    bt_push([NSString stringWithFormat:@"restorefailed:%@",
             error.localizedDescription ?: @""]);
}

@end

BT_EXPORT void bt_iap_init(const char *productId) {
    if (bt_store) return;
    bt_events = [NSMutableArray new];
    bt_store = [BTStore new];
    bt_productId = [NSString stringWithUTF8String:productId];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:bt_store];
    bt_request = [[SKProductsRequest alloc]
        initWithProductIdentifiers:[NSSet setWithObject:bt_productId]];
    bt_request.delegate = bt_store;
    [bt_request start];
    NSLog(@"[bt_iap] init: %@", bt_productId);
}

BT_EXPORT void bt_iap_buy(void) {
    if (![SKPaymentQueue canMakePayments]) {
        bt_push(@"failed:Kjøp er ikke tillatt på denne enheten");
        return;
    }
    if (!bt_product) {
        bt_push(@"failed:Fikk ikke kontakt med App Store");
        return;
    }
    [[SKPaymentQueue defaultQueue] addPayment:[SKPayment paymentWithProduct:bt_product]];
}

BT_EXPORT void bt_iap_restore(void) {
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

BT_EXPORT const char *bt_iap_poll(void) {
    static char buf[512];
    if (bt_events.count == 0) return NULL;
    NSString *ev = bt_events.firstObject;
    [bt_events removeObjectAtIndex:0];
    strlcpy(buf, ev.UTF8String, sizeof(buf));
    return buf;
}

BT_EXPORT const char *bt_iap_price(void) {
    static char buf[64];
    if (!bt_priceStr) return NULL;
    strlcpy(buf, bt_priceStr.UTF8String, sizeof(buf));
    return buf;
}
