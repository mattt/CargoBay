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

#import "AFHTTPClient.h"
#import "AFJSONRequestOperation.h"

NSString * const CargoBarErrorDomain = @"CargoBarErrorDomain";

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
                  success:(void (^)(NSDictionary *receipt))success
                  failure:(void (^)(NSError *error))failure
{
    if (transaction.transactionState != SKPaymentTransactionStatePurchased) {
        return;
    }
    
    [_receiptVerificationClient getPath:@"verifyReceipt" parameters:[NSDictionary dictionaryWithObject:CBBase64EncodedStringFromData(transaction.transactionReceipt) forKey:@"receipt-data"] success:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSInteger status = [[responseObject valueForKey:@"status"] integerValue];
        if (status == 0) {
            if (success) {
                NSDictionary *receipt = [responseObject valueForKey:@"receipt"];
                success(receipt);
            }
        } else {
            if (failure) {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[responseObject valueForKey:@"exception"] forKey:NSLocalizedFailureReasonErrorKey];
                
                NSError *error = [[NSError alloc] initWithDomain:CargoBarErrorDomain code:status userInfo:userInfo];
                failure(error);
            }
        }
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(error);
        }
    }];
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

- (id)initWithSuccess:(void (^)(NSArray *, NSArray *))success failure:(void (^)(NSError *))failure {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _success = [success copy];
    _failure = [failure copy];
    
    return self;
}

#pragma mark - SKRequestDelegate

- (void)request:(SKRequest *)request
didFailWithError:(NSError *)error
{
    if (_failure) {
        _failure(error);
    }
    
    [[self class] unregisterDelegate:self];
}

#pragma mark - SKProductsRequestDelegate

- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    if (_success) {
        _success(response.products, response.invalidProductIdentifiers);
    }
    
    [[self class] unregisterDelegate:self];
}

@end
