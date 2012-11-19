// CargoBay.m
//
// Copyright (c) 2012 Mattt Thompson (http://mattt.me/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "CargoBay.h"

#import <Availability.h>

#import "AFHTTPClient.h"
#import "AFJSONRequestOperation.h"

static NSString * const kCargoBayReceiptVerificationBaseURLString = @"https://buy.itunes.apple.com/";

typedef void (^CargoBayPaymentQueueProductSuccessBlock)(NSArray *products, NSArray *invalidIdentifiers);
typedef void (^CargoBayPaymentQueueProductFailureBlock)(NSError *error);
typedef void (^CargoBayPaymentQueueTransactionsBlock)(SKPaymentQueue *queue, NSArray *transactions);
typedef void (^CargoBayPaymentQueueRestoreSuccessBlock)(SKPaymentQueue *queue);
typedef void (^CargoBayPaymentQueueRestoreFailureBlock)(SKPaymentQueue *queue, NSError *error);

static NSString * CBBase64EncodedStringFromData(NSData *data) {
    NSUInteger length = [data length];
    NSMutableData *mutableData = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    
    uint8_t *input = (uint8_t *)[data bytes];
    uint8_t *output = (uint8_t *)[mutableData mutableBytes];
    
    for (NSUInteger i = 0; i < length; i += 3) {
        NSUInteger value = 0;
        for (NSUInteger j = i; j < (i + 3); j++) {
            value <<= 8;
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }
        
        static uint8_t const kAFBase64EncodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        
        NSUInteger idx = (i / 3) * 4;
        output[idx + 0] = kAFBase64EncodingTable[(value >> 18) & 0x3F];
        output[idx + 1] = kAFBase64EncodingTable[(value >> 12) & 0x3F];
        output[idx + 2] = (i + 1) < length ? kAFBase64EncodingTable[(value >> 6)  & 0x3F] : '=';
        output[idx + 3] = (i + 2) < length ? kAFBase64EncodingTable[(value >> 0)  & 0x3F] : '=';
    }
    
    return [[NSString alloc] initWithData:mutableData encoding:NSASCIIStringEncoding];
}

static BOOL CBValidateTrust(SecTrustRef trust, NSError * __autoreleasing *error) {
#ifdef _SECURITY_SECBASE_H_
    extern CFStringRef kSecTrustInfoExtendedValidationKey;
    extern CFDictionaryRef SecTrustCopyInfo(SecTrustRef trust);
    
    NSCParameterAssert(trust);
    
    SecTrustResultType result;
    if ((noErr == SecTrustEvaluate(trust, &result)) && (result == kSecTrustResultUnspecified)) {
        id extendedValidation = [(__bridge_transfer NSDictionary *)SecTrustCopyInfo(trust) objectForKey:(__bridge NSString *)kSecTrustInfoExtendedValidationKey];
        return [extendedValidation isKindOfClass:[NSValue class]] && [extendedValidation boolValue];
    } else {
        if (error){
            *error = [NSError errorWithDomain:@"kSecTrustError" code:(NSInteger)result userInfo:nil];
        }
    }

    return NO;
#else
    return YES;
#endif
}

static BOOL CBValidateTransactionMatchesReceipt(SKPaymentTransaction *transaction, NSDictionary *receipt, NSError * __autoreleasing *error) {
    NSDictionary *transactionReceipt = [NSPropertyListSerialization propertyListWithData:transaction.transactionReceipt options:NSPropertyListImmutable format:nil error:error];
        
    if (![[receipt objectForKey:@"bid"] isEqual:[transactionReceipt objectForKey:@"bid"]]) {
        return NO;
    } else if (![[receipt objectForKey:@"product_id"] isEqual:[transactionReceipt objectForKey:@"product-id"]]) {
        return NO;
    } else if (![[receipt objectForKey:@"quantity"] isEqual:[transactionReceipt objectForKey:@"quantity"]]) {
        return NO;
    } else if (![[receipt objectForKey:@"item_id"] isEqual:[transactionReceipt objectForKey:@"item-id"]]) {
        return NO;
    }

    if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"identifierForVendor")]) {
#ifdef __IPHONE_6_0
        NSString *deviceIdentifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        NSString *transactionUniqueVendorIdentifier = [transactionReceipt objectForKey:@"unique-vendor-identifier"];
        NSString *receiptVendorIdentifier = [receipt objectForKey:@"unique_vendor_identifier"];
        
        if(receiptVendorIdentifier) {
            if (![transactionUniqueVendorIdentifier isEqual:receiptVendorIdentifier] || ![transactionUniqueVendorIdentifier isEqual:deviceIdentifier])
            {
            #if !TARGET_IPHONE_SIMULATOR
                return NO;
            #endif
            }
        }
#endif
    } else if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"uniqueIdentifier")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSString *deviceIdentifier = [[UIDevice currentDevice] uniqueIdentifier];
#pragma clang diagnostic pop
        NSString *transactionUniqueIdentifier = [transactionReceipt objectForKey:@"unique-identifier"];
        NSString *receiptUniqueIdentifier = [receipt objectForKey:@"unique_identifier"];
        if (![transactionUniqueIdentifier isEqual:receiptUniqueIdentifier] || ![transactionUniqueIdentifier isEqual:deviceIdentifier])
        {
            return NO;
        }
    }

    return YES;
}

@interface CargoBayProductRequestDelegate : NSObject <SKRequestDelegate, SKProductsRequestDelegate> {
@private
    CargoBayPaymentQueueProductSuccessBlock _success;
    CargoBayPaymentQueueProductFailureBlock _failure;
}

+ (void)registerDelegate:(CargoBayProductRequestDelegate *)delegate;
+ (void)unregisterDelegate:(CargoBayProductRequestDelegate *)delegate;

- (id)initWithSuccess:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
              failure:(void (^)(NSError *error))failure;
@end

#pragma mark -

@implementation CargoBay {
@private
    AFHTTPClient *_receiptVerificationClient;
        
    CargoBayPaymentQueueTransactionsBlock _paymentQueueTransactionsUpdated;
    CargoBayPaymentQueueTransactionsBlock _paymentQueueTransactionsRemoved;
    CargoBayPaymentQueueRestoreSuccessBlock _paymentQueueRestoreSuccessBlock;
    CargoBayPaymentQueueRestoreFailureBlock _paymentQueueRestoreFailureBlock;
}

+ (CargoBay *)sharedManager {
    static CargoBay *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[CargoBay alloc] init];
    });
    
    return _sharedManager;
}

- (id)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _receiptVerificationClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:kCargoBayReceiptVerificationBaseURLString]];
    [_receiptVerificationClient setDefaultHeader:@"Accept" value:@"application/json"];
    [_receiptVerificationClient registerHTTPOperationClass:[AFJSONRequestOperation class]];
    [_receiptVerificationClient setParameterEncoding:AFJSONParameterEncoding];
    [AFJSONRequestOperation addAcceptableContentTypes:[NSSet setWithObject:@"text/plain"]];
        
    return self;
}

- (void)productsWithIdentifiers:(NSSet *)identifiers
                        success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                        failure:(void (^)(NSError *error))failure
{
    SKProductsRequest *request = [[SKProductsRequest alloc] initWithProductIdentifiers:identifiers];
    
    id <SKProductsRequestDelegate> delegate = [[CargoBayProductRequestDelegate alloc] initWithSuccess:success failure:failure];
    request.delegate = delegate;
    
    [CargoBayProductRequestDelegate registerDelegate:delegate];
    [request start];
}

- (void)productsWithRequest:(NSURLRequest *)request
                    success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                    failure:(void (^)(NSError *error))failure
{
    if (!_productsHTTPClient) {
        return;
    }
    
    AFHTTPRequestOperation *operation = [_productsHTTPClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        if (success && [responseObject isKindOfClass:[NSArray class]]) {
            [self productsWithIdentifiers:[NSSet setWithArray:responseObject] success:success failure:failure];
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(error);
        }
    }];

    [_productsHTTPClient.operationQueue addOperation:operation];
}

- (void)verifyTransaction:(SKPaymentTransaction *)transaction
                 password:(NSString *)password
                  success:(void (^)(NSDictionary *receipt))success
                  failure:(void (^)(NSError *error))failure
{
    if (transaction.transactionState != SKPaymentTransactionStatePurchased) {
        return;
    }
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithObject:CBBase64EncodedStringFromData(transaction.transactionReceipt) forKey:@"receipt-data"];
    if (password) {
        [parameters setObject:password forKey:@"password"];
    }
    
    NSURLRequest *request = [_receiptVerificationClient requestWithMethod:@"POST" path:@"verifyReceipt" parameters:parameters];
    AFHTTPRequestOperation *operation = [_receiptVerificationClient HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSInteger status = [responseObject valueForKey:@"status"] ? [[responseObject valueForKey:@"status"] integerValue] : NSNotFound;
        
        // Status 0: The receipt is valid.
        // Status 21006: This receipt is valid but the subscription has expired.
        if (status == 0 || status == 21006) {
            NSDictionary *receipt = [responseObject valueForKey:@"receipt"];
            NSError *error = nil;
            
            BOOL isValid = CBValidateTransactionMatchesReceipt(transaction, receipt, &error);
            if (isValid) {
                if (success) {
                    success(receipt);
                }
            } else {
                if (failure) {
                    failure(error);
                }
            }
        } else {
            if (failure) {
                NSString *exception = [responseObject valueForKey:@"exception"];
                NSDictionary *userInfo = exception ? [NSDictionary dictionaryWithObject:exception forKey:NSLocalizedFailureReasonErrorKey] : nil;
                
                NSError *error = [[NSError alloc] initWithDomain:SKErrorDomain code:status userInfo:userInfo];
                failure(error);
            }
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(error);
        }
    }];
    
    [operation setAuthenticationAgainstProtectionSpaceBlock:^BOOL(NSURLConnection *connection, NSURLProtectionSpace *protectionSpace) {
        return [[protectionSpace authenticationMethod] isEqual:NSURLAuthenticationMethodServerTrust];
    }];
    
    [operation setAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
        if ([[[challenge protectionSpace] authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            SecTrustRef trust = [[challenge protectionSpace] serverTrust];
            NSError *error = nil;
            
            BOOL didUseCredential = NO;
            BOOL isTrusted = CBValidateTrust(trust, &error);
            if (isTrusted) {
                NSURLCredential *credential = [NSURLCredential credentialForTrust:trust];
                if (credential) {
                    [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                    didUseCredential = YES;
                }
            }
            
            if (!didUseCredential) {
                [[challenge sender] cancelAuthenticationChallenge:challenge];
            }
        } else {
            [[challenge sender] performDefaultHandlingForAuthenticationChallenge:challenge];
        }
    }];
    
    [_receiptVerificationClient enqueueHTTPRequestOperation:operation];
}

- (void)verifyTransaction:(SKPaymentTransaction *)transaction
                  success:(void (^)(NSDictionary *receipt))success
                  failure:(void (^)(NSError *error))failure
{
    [self verifyTransaction:transaction password:nil success:success failure:failure];
}

- (void)setPaymentQueueUpdatedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block {
    _paymentQueueTransactionsUpdated = [block copy];
}

- (void)setPaymentQueueRemovedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block {
    _paymentQueueTransactionsRemoved = [block copy];
}

- (void)setPaymentQueueRestoreCompletedTransactionsWithSuccess:(void (^)(SKPaymentQueue *queue))success
                                                       failure:(void (^)(SKPaymentQueue *queue, NSError *error))failure
{
    _paymentQueueRestoreSuccessBlock = [success copy];
    _paymentQueueRestoreFailureBlock = [failure copy];
}

#pragma mark - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    if (_paymentQueueTransactionsUpdated) {
        _paymentQueueTransactionsUpdated(queue, transactions);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 removedTransactions:(NSArray *)transactions
{
    if (_paymentQueueTransactionsRemoved) {
        _paymentQueueTransactionsRemoved(queue, transactions);
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    if (_paymentQueueRestoreSuccessBlock) {
        _paymentQueueRestoreSuccessBlock(queue);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    if (_paymentQueueRestoreFailureBlock) {
        _paymentQueueRestoreFailureBlock(queue, error);
    }
}

@end

#pragma mark -

@interface CargoBayProductRequestDelegate ()
+ (NSMutableSet *)registeredDelegates;
@end

@implementation CargoBayProductRequestDelegate

+ (NSMutableSet *)registeredDelegates {
    static NSMutableSet *_mutableRegisteredDelegates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _mutableRegisteredDelegates = [[NSMutableSet alloc] init];
    });
    
    return _mutableRegisteredDelegates;
}

+ (void)registerDelegate:(CargoBayProductRequestDelegate *)delegate {
    [[self registeredDelegates] addObject:delegate];
}

+ (void)unregisterDelegate:(CargoBayProductRequestDelegate *)delegate {
    [[self registeredDelegates] removeObject:delegate];
}

- (id)initWithSuccess:(void (^)(NSArray *, NSArray *))success
              failure:(void (^)(NSError *))failure
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
#if __has_feature(objc_arc_weak)
    __weak __typeof(&*self)weakSelf = self;
#else
    __unsafe_unretained __typeof(&*self)weakSelf = self;
#endif
    
    _success = [^(NSArray *products, NSArray *invalidIdentifiers) {
        if (success) {
            success(products, invalidIdentifiers);
        }
        
        [[self class] unregisterDelegate:weakSelf];
    } copy];
    
    _failure = [^(NSError *error) {
        if (failure) {
            failure(error);
        }
        
        [[self class] unregisterDelegate:weakSelf];
    } copy];

    
    return self;
}

#pragma mark - SKRequestDelegate

- (void)request:(SKRequest *)request
didFailWithError:(NSError *)error
{
    if (_failure) {
        _failure(error);
    }    
}

#pragma mark - SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    if (_success) {
        _success(response.products, response.invalidProductIdentifiers);
    }    
}

@end
