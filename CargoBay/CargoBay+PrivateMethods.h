//
//  CargoBay+PrivateMethods.h
//  
//
//  Created by Stan Chang Khin Boon on 18/12/12.
//
//

#import "CargoBay.h"

@class AFHTTPClient;

@interface CargoBay ()

+ (NSString *)_base64EncodedStringFromData:(NSData *)data;
+ (NSData *)_dataFromBase64EncodedString:(NSString *)theBase64EncodedString;
+ (BOOL)_validateTrust:(SecTrustRef)trust error:(NSError * __autoreleasing *)error;
+ (BOOL)_validatePurchaseInfo:(NSDictionary *)purchaseInfo matchesReceipt:(NSDictionary *)receipt error:(NSError * __autoreleasing *)error;
+ (BOOL)_validateTransaction:(SKPaymentTransaction *)theTransaction matchesPurchaseInfo:(NSDictionary *)thePurchaseInfoDictionary error:(NSError * __autoreleasing *)theError;
+ (BOOL)_checkReceiptSecurityWithPurchaseInfo:(NSString *)thePurchaseInfoString signature:(NSString *)theSignatureString purchaseDate:(CFDateRef)thePurchaseDate;
+ (NSDictionary *)_purchaseInfoFromTransactionReceipt:(NSData *)theTransactionReceiptData error:(NSError * __autoreleasing *)theError;

- (AFHTTPClient *)sandboxReceiptVerificationClient;
- (AFHTTPClient *)productionReceiptVerificationClient;

- (void)verifyTransactionReceipt:(NSData *)transactionReceipt
                          client:(AFHTTPClient *)client
                        password:(NSString *)password
                         success:(void (^)(NSDictionary *responseObject))success
                         failure:(void (^)(NSError *error))failure;

@end
