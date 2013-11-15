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
#import <Security/Security.h>

/**
 `CargoBay` provides a convenient block-based API to StoreKit functionality, as well as advanced functionality like receipt and transaction verification and external product information querying.
 
 ## Product Information Lookup
 
 Localized product information can be queried from a set of known identifiers or fetched from an external webservice.

 ## Transaction & Receipt Verification
 
 Completed transactions contains a signed receipt that records all the critical information for the transaction. This can be easily posted to the App Store to verify that the receipt is valid and has not been tampered with. Transactions can also be validated to be unique, according to a local or remote database.

 ## Transaction Queue Observer Delegate Methods
 
 The `SKPaymentTransactionObserver` protocol declares methods that are implemented by `CargoBay`, acting as an observer of the `SKPaymentQueue` object. Observer delegate methods are provided as block callbacks for convenience.
 */
@interface CargoBay : NSObject <SKPaymentTransactionObserver>

/**
 Returns the shared CargoBay manager for the application.
 
 @return The shared CargoBay manager.
 */
+ (instancetype)sharedManager;

///---------------------------------
/// @name Product Information Lookup
///---------------------------------

/**
 Performs an `SKProductsRequest` with the specified product identifiers.

 @param identifiers The identifiers to have their corresponding products' localized information retrieved.
 @param success A block object to be executed when the request finishes successfully. This block has no return value and takes two arguments: a list of products, one product for each valid product identifier provided and an array of product identifier strings that were not recognized by the Apple App Store.
 @param failure A block object to be executed when the request finishes unsuccessfully. This block has no return value and takes a single arguments: the error that caused the request to fail.
 */
- (void)productsWithIdentifiers:(NSSet *)identifiers
                        success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                        failure:(void (^)(NSError *error))failure;

/**
 Fetches product identifiers from an external webservice and performs an `SKProductsRequest`.

 @param request The request object to be loaded asynchronously to retrieve an array of identifiers.
 @param success A block object to be executed when the request finishes successfully. This block has no return value and takes two arguments: a list of products, one product for each valid product identifier provided and an array of product identifier strings that were not recognized by the Apple App Store.
 @param failure A block object to be executed when the request finishes unsuccessfully. This block has no return value and takes a single arguments: the error that caused the request to fail.
 
 @discussion Product identifiers are expected to be returned as a JSON array from the webservice.
 */
- (void)productsWithRequest:(NSURLRequest *)request
                    success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                    failure:(void (^)(NSError *error))failure;

///-----------------------------------------
/// @name Transaction & Receipt Verification
///-----------------------------------------

/**
 Verifies that a transaction is in a purchased or restored state, and if so, verifies its receipt with the App Store.
 
 @param transaction The transaction to be verified.
 @param passwordOrNil The password associated with the transaction if the transaction was for an auto-renewable subscription, or `nil`.
 @param success A block object to be executed when the verification finishes successfully. This block has no return value and takes a single argument: the receipt details of the transaction.
 @param failure A block object to be executed when the verification fails or finishes unsuccessfully. This block has no return value and takes a single argument: the error that caused the request to fail.
 
 @see -verifyTransactionReceipt:password:success:failure:
 */
- (void)verifyTransaction:(SKPaymentTransaction *)transaction
                 password:(NSString *)passwordOrNil
                  success:(void (^)(NSDictionary *receipt))success
                  failure:(void (^)(NSError *error))failure;

/**
 Sets a block to be executed in order to determine whether a transaction ID is unique. When set, `-verifyTransaction:password:success:failure:` will call the specified block as part of its verification. Otherwise, no uniqueness verification is performed.

 @param block A block object to be executed as part of transaction verification. This block takes a single argument, a transaction ID, and returns whether the provided transaction ID is unique.
 
 @discussion Applications can use this block to enforce unique transaction IDs, such as by checking against a local database of transaction IDs or querying an external webservice. CargoBay does not provide any transaction ID management, instead leaving this as an exercise for the user.
 */
- (void)setTransactionIDUniquenessVerificationWithBlock:(BOOL (^)(NSString *transactionID))block;

/**
 Verifies a transaction receipt with the App Store.

 @param transactionReceipt The receipt to be verified.
 @param passwordOrNil The password associated with the transaction if the transaction was for an auto-renewable subscription, or `nil`.
 @param success A block object to be executed when the verification finishes successfully. This block has no return value and takes a single argument: the receipt details of the transaction.
 @param failure A block object to be executed when the verification fails or finishes unsuccessfully. This block has no return value and takes a single argument: the error that caused the request to fail.
 */
- (void)verifyTransactionReceipt:(NSData *)transactionReceipt
                        password:(NSString *)passwordOrNil
                         success:(void (^)(NSDictionary *responseObject))success
                         failure:(void (^)(NSError *error))failure;

/**
 Verifies a transaction receipt with a custom webservice endpoint.

 @param transactionReceipt The receipt to be verified.
 @param method The HTTP method of the URL request.
 @param endpoint The URL endpoint of the webservice
 @param password The password associated with the transaction if the transaction was for an auto-renewable subscription, or `nil`.
 @param success A block object to be executed when the verification finishes successfully. This block has no return value and takes a single argument: the receipt details of the transaction.
 @param failure A block object to be executed when the verification fails or finishes unsuccessfully. This block has no return value and takes a single argument: the error that caused the request to fail.
 */
- (void)verifyTransactionWithMethod:(NSString *)method
                           endpoint:(NSURL *)endpoint
                            receipt:(NSData *)transactionReceipt
                           password:(NSString *)password
                            success:(void (^)(NSDictionary *responseObject))success
                            failure:(void (^)(NSError *error))failure;

///--------------------------------------------------
/// @name Transaction Queue Observer Delegate Methods
///--------------------------------------------------

/**
 Sets a block to be called when one or more transactions have been updated.
 
 @param block A block object to be executed when one or more transactions have been updated. The block has no return value and takes two arguments: the notifying payment queue, and the updated transactions.
 */
- (void)setPaymentQueueUpdatedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block;

/**
 Sets a block to be called when one or more transactions have been removed from the queue.
 
 @param block A block object to be executed when one or more transactions have been removed from a payment queue. The block has no return value and takes two arguments: the notifying payment queue, and the removed transactions.
 */
- (void)setPaymentQueueRemovedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block;

/**
 Sets a block to be called when the payment queue has finished sending restored transactions
 
 @param success A block object to be executed when the payment queue has finished sending restored transactions. The block has no return value and takes a single argument: the notifying payment queue.
 @param failure A block object to be executed when an error occurred while restoring transactions. The block has no return value and takes two arguments: the notifying payment queue and the error that occurred.
 */
- (void)setPaymentQueueRestoreCompletedTransactionsWithSuccess:(void (^)(SKPaymentQueue *queue))success
                                                       failure:(void (^)(SKPaymentQueue *queue, NSError *error))failure;
/**
 Sets a block to be called when the payment queue has updated one or more download objects.
 
 @param block A block object to be executed when the payment queue has updated one or more download objects. The block has no return value and takes two arguments: the notifying payment queue and the download objects that were updated.
 
 @discussion When a download object is updated, its `downloadState` property describes how it changed.
 */
- (void)setPaymentQueueUpdatedDownloadsBlock:(void (^)(SKPaymentQueue *queue, NSArray *downloads))block;

@end

///----------------
/// @name Constants
///----------------

/**
 ## Receipt Verification Endpoints
 
 `kCargoBaySandboxReceiptVerificationURLString`: https://sandbox.itunes.apple.com/verifyReceipt
 `kCargoBayProductionReceiptVerificationURLString`: https://buy.itunes.apple.com/verifyReceipt

 ## Error Domains

 The following error domain is predefined.

 - `NSString * const CargoBayErrorDomain`
 
 ## Error Codes

 The following constants are used as codes for errors within the `CargoBayErrorDomain`.

 enum {
 CargoBayErrorUnknown,

 CargoBayErrorPurchaseInfoDoesNotMatchReceipt,
 CargoBayErrorTransactionDoesNotMatchesPurchaseInfo,
 CargoBayErrorCannotExtractPurchaseInfoFromTransactionReceipt,
 CargoBayErrorTransactionNotInPurchasedOrRestoredState,
 CargoBayErrorTransactionNotValid,
 CargoBayErrorTransactionIDNotUnique,

 // Error codes derived from status codes for auto-renewable subscriptions
 CargoBayErrorCannotParseJSON,
 CargoBayErrorMalformedReceiptData,
 CargoBayErrorCannotAuthenticateReceiptData,
 CargoBayErrorSharedSecretDoesNotMatch,
 CargoBayErrorReceiptServerUnavailable,
 }
 */
extern NSString * const kCargoBaySandboxReceiptVerificationURLString;
extern NSString * const kCargoBayProductionReceiptVerificationURLString;

extern NSString * const CargoBayErrorDomain;

typedef NS_ENUM(NSInteger, CargoBayStatusCode) {
    CargoBayStatusOK = 0,

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
    CargoBayErrorTransactionIDNotUnique = 6,

    // Error codes derived from status codes for auto-renewable subscriptions
    CargoBayErrorCannotParseJSON = CargoBayStatusCannotParseJSON,
    CargoBayErrorMalformedReceiptData = CargoBayStatusMalformedReceiptData,
    CargoBayErrorCannotAuthenticateReceiptData = CargoBayStatusCannotAuthenticateReceiptData,
    CargoBayErrorSharedSecretDoesNotMatch = CargoBayStatusSharedSecretDoesNotMatch,
    CargoBayErrorReceiptServerUnavailable = CargoBayStatusReceiptServerUnavailable
};
