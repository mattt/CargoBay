// CargoBay.h
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

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

#ifndef _SECURITY_SECBASE_H_
#warning Security framework not found in project, or not included in precompiled header. Server trust validation on receipt verifications will not be available.
#endif

@class AFHTTPClient;

extern NSString * const CargoBayErrorDomain;

typedef NS_ENUM(NSInteger, CargoBayStatusCode) {
    CargoBayStatusOK = 0,
    
    // Status codes for auto-renewable subscriptions
    CargoBayStatusCannotParseJSON = 21000,
    CargoBayStatusMalformedReceiptData = 21002,
    CargoBayStatusCannotAuthenticateReceiptData = 21003,
    CargoBayStatusSharedSecretDoesNotMatch = 21004,
    CargoBayStatusReceiptServerUnavailable = 21005,
    CargoBayStatusReceiptValidButSubscriptionExpired = 21006,
    CargoBayStatusSandboxReceiptSentToProduction = 21007,
    CargoBayStatusProductionReceiptSentToSandbox = 21008
};

typedef NS_ENUM(NSInteger, CargoBayErrorCode) {
    CargoBayErrorUnknown = -1,
    
    CargoBayErrorPurchaseInfoDoesNotMatchReceipt = 1,
    CargoBayErrorTransactionDoesNotMatchesPurchaseInfo = 2,
    CargoBayErrorCannotExtractPurchaseInfoFromTransactionReceipt = 3,
    CargoBayErrorTransactionNotInPurchasedOrRestoredState = 4,
    CargoBayErrorTransactionNotValid = 5,
    
    // Error codes derived from status codes for auto-renewable subscriptions
    CargoBayErrorCannotParseJSON = CargoBayStatusCannotParseJSON,
    CargoBayErrorMalformedReceiptData = CargoBayStatusMalformedReceiptData,
    CargoBayErrorCannotAuthenticateReceiptData = CargoBayStatusCannotAuthenticateReceiptData,
    CargoBayErrorSharedSecretDoesNotMatch = CargoBayStatusSharedSecretDoesNotMatch,
    CargoBayErrorReceiptServerUnavailable = CargoBayStatusReceiptServerUnavailable
};

@interface CargoBay : NSObject <SKPaymentTransactionObserver>

@property (nonatomic) AFHTTPClient *productsHTTPClient;

+ (CargoBay *)sharedManager;

///---------------------
/// @name Product Lookup
///---------------------

- (void)productsWithIdentifiers:(NSSet *)identifiers
                        success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                        failure:(void (^)(NSError *error))failure;

- (void)productsWithRequest:(NSURLRequest *)request
                    success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                    failure:(void (^)(NSError *error))failure;

///-------------------------------
/// @name Transaction Verification
///-------------------------------

- (void)verifyTransaction:(SKPaymentTransaction *)transaction
                 password:(NSString *)password
                  success:(void (^)(NSDictionary *receipt))success
                  failure:(void (^)(NSError *error))failure;

- (void)verifyTransaction:(SKPaymentTransaction *)transaction
                  success:(void (^)(NSDictionary *receipt))success
                  failure:(void (^)(NSError *error))failure;

///---------------------------------------
/// @name Transaction Receipt Verification
///---------------------------------------

- (void)verifyTransactionReceipt:(NSData *)transactionReceipt
                        password:(NSString *)password
                         success:(void (^)(NSDictionary *responseObject))success
                         failure:(void (^)(NSError *error))failure;

- (void)verifyTransactionReceipt:(NSData *)transactionReceipt
                         success:(void (^)(NSDictionary *responseObject))success
                         failure:(void (^)(NSError *error))failure;

///--------------------------------------------------
/// @name Transaction Queue Observer Delegate Methods
///--------------------------------------------------

- (void)setPaymentQueueUpdatedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block;

- (void)setPaymentQueueRemovedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block;

- (void)setPaymentQueueRestoreCompletedTransactionsWithSuccess:(void (^)(SKPaymentQueue *queue))success
                                                       failure:(void (^)(SKPaymentQueue *queue, NSError *error))failure;

@end
