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

#import "AFHTTPRequestOperationManager.h"
#import "AFHTTPRequestOperation.h"

#import <AssertMacros.h>

NSString * const CargoBayErrorDomain = @"com.mattt.CargoBay.ErrorDomain";

NSString * const kCargoBaySandboxReceiptVerificationURLString = @"https://sandbox.itunes.apple.com/verifyReceipt";
NSString * const kCargoBayProductionReceiptVerificationURLString = @"https://buy.itunes.apple.com/verifyReceipt";

static NSString * const kCargoBayKnownIAPTransactionsKey = @"com.mattt.CargoBay.knownIAPTransactions";

typedef void (^CargoBayPaymentQueueProductSuccessBlock)(NSArray *products, NSArray *invalidIdentifiers);
typedef void (^CargoBayPaymentQueueProductFailureBlock)(NSError *error);
typedef void (^CargoBayPaymentQueueTransactionsBlock)(SKPaymentQueue *queue, NSArray *transactions);
typedef void (^CargoBayPaymentQueueRestoreSuccessBlock)(SKPaymentQueue *queue);
typedef void (^CargoBayPaymentQueueRestoreFailureBlock)(SKPaymentQueue *queue, NSError *error);
typedef void (^CargoBayPaymentQueueUpdatedDownloadsBlock)(SKPaymentQueue *queue, NSArray *downloads);
typedef BOOL (^CargoBayTransactionIDUniquenessVerificationBlock)(NSString *transactionID);

extern NSDate * CBDateFromDateString(NSString *);
extern NSString * CBBase64EncodedStringFromData(NSData *);
extern NSData * CBDataFromBase64EncodedString(NSString *);
extern BOOL CBValidateTrust(SecTrustRef, NSError * __autoreleasing *);
extern BOOL CBValidatePurchaseInfoMatchesReceiptForDevice(NSDictionary *, NSDictionary *, __unused NSError * __autoreleasing *);
extern BOOL CBValidatePurchaseInfoMatchesReceipt(NSDictionary *, NSDictionary *, NSError * __autoreleasing *);
extern BOOL CBValidateTransactionMatchesPurchaseInfo(SKPaymentTransaction *, NSDictionary *, NSError * __autoreleasing *);
extern BOOL CBCheckReceiptSecurity(NSString *, NSString *, NSDate *);
extern NSData * CBTransactionReceiptFromPaymentTransaction(SKPaymentTransaction *);
extern NSDictionary * CBPurchaseInfoFromTransactionReceipt(NSData *,  NSError * __autoreleasing *);

NSDate * CBDateFromDateString(NSString *string) {
    if (!string) {
        return nil;
    }

    NSString *dateString = [string stringByReplacingOccurrencesOfString:@"Etc/" withString:@""];

    static NSDateFormatter *_dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _dateFormatter =  [[NSDateFormatter alloc] init];
        _dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss z";
    });

    return [_dateFormatter dateFromString:dateString];
}

NSString * CBBase64EncodedStringFromData(NSData *data) {
    NSUInteger length = [data length];
    NSMutableData *mutableData = [NSMutableData dataWithLength:((length + 2) / 3) * 4];

    uint8_t *input = (uint8_t *)[data bytes];
    uint8_t *output = (uint8_t *)[mutableData mutableBytes];

    static uint8_t const kAFBase64EncodingTable[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    for (NSUInteger i = 0; i < length; i += 3) {
        NSUInteger value = 0;
        for (NSUInteger j = i; j < (i + 3); j++) {
            value <<= 8;
            if (j < length) {
                value |= (0xFF & input[j]);
            }
        }

        NSUInteger idx = (i / 3) * 4;
        output[idx + 0] = kAFBase64EncodingTable[(value >> 18) & 0x3F];
        output[idx + 1] = kAFBase64EncodingTable[(value >> 12) & 0x3F];
        output[idx + 2] = (i + 1) < length ? kAFBase64EncodingTable[(value >> 6)  & 0x3F] : '=';
        output[idx + 3] = (i + 2) < length ? kAFBase64EncodingTable[(value >> 0)  & 0x3F] : '=';
    }

    return [[NSString alloc] initWithData:mutableData encoding:NSASCIIStringEncoding];
}

NSData * CBDataFromBase64EncodedString(NSString *base64EncodedString) {
    NSData *base64EncodedStringASCIIData = [base64EncodedString dataUsingEncoding:NSASCIIStringEncoding];
    uint8_t *input = (uint8_t *)base64EncodedStringASCIIData.bytes;
    NSUInteger length = base64EncodedStringASCIIData.length;

    NSUInteger outputLength = ((length + 3) / 4) * 3;
    if (input[length - 1] == 61) {
        if (input[length - 2] == 61) {
            outputLength -= 2;
        } else {
            outputLength -= 1;
        }
    }

    NSMutableData *data = [NSMutableData dataWithLength:outputLength];
    uint8_t *output = (uint8_t *)data.mutableBytes;

    static uint8_t const kAFBase64DecodingTable[256] = {
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 62,  0,  0,  0, 63,
        52, 53, 54, 55, 56, 57, 58, 59, 60, 61,  0,  0,  0,  0,  0,  0,
        0,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
        15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,  0,  0,  0,  0,  0,
        0, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
        0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    };

    for (NSUInteger i = 0; i < length; i += 4) {
        NSUInteger value = 0;
        for (NSUInteger j = i; j < (i + 4); j++) {
            value <<= 6;
            if (j < length) {
                value |= (0x3F & kAFBase64DecodingTable[input[j]]);
            }
        }

        NSUInteger outputIndex = (i / 4) * 3;
        output[outputIndex + 0] = (value >> 16) & 0xFF;
        output[outputIndex + 1] = (value >> 8) & 0xFF;
        output[outputIndex + 2] = (value >> 0) & 0xFF;
    }

    return [NSData dataWithData:data];
}

BOOL CBValidateTrust(SecTrustRef trust, NSError * __autoreleasing *error) {
#if defined(_SECURITY_SECBASE_H_) && !defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
    extern CFStringRef kSecTrustInfoExtendedValidationKey;
    extern CFDictionaryRef SecTrustCopyInfo(SecTrustRef trust);

    NSCParameterAssert(trust);

    BOOL trusted = NO;
    SecTrustResultType result;
    if ((noErr == SecTrustEvaluate(trust, &result)) && (result == kSecTrustResultUnspecified)) {
        NSDictionary *trust_info = (__bridge_transfer NSDictionary *)SecTrustCopyInfo(trust);
        id extendedValidation = [trust_info objectForKey:(__bridge NSString *)kSecTrustInfoExtendedValidationKey];
        trusted = [extendedValidation isKindOfClass:[NSValue class]] && [extendedValidation boolValue];
    }

    if (!trusted) {
        if (error) {
            *error = [NSError errorWithDomain:@"kSecTrustError" code:(NSInteger)result userInfo:nil];
        }
        
        return NO;
    }
#else
#pragma unused (trust, error)
#endif
    
    return YES;
}

BOOL CBValidatePurchaseInfoMatchesReceipt(NSDictionary *purchaseInfo, NSDictionary *receipt, NSError * __autoreleasing *error) {
    if (![[receipt objectForKey:@"bid"] isEqual:[purchaseInfo objectForKey:@"bid"]]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info does not match receipt because purchase info's bundle ID (%@) does not match receipt's bundle ID (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"bid"], [receipt objectForKey:@"bid"]] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info's bundle ID (%@) does not match receipt's bundle ID (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"bid"], [receipt objectForKey:@"bid"]] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorPurchaseInfoDoesNotMatchReceipt userInfo:userInfo];
        }
        
        return NO;
    } else if (![[receipt objectForKey:@"product_id"] isEqual:[purchaseInfo objectForKey:@"product-id"]]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info does not match receipt because purchase info's product ID (%@) does not match receipt's product ID (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"product-id"], [receipt objectForKey:@"product_id"]] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info's product ID (%@) does not match receipt's product ID (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"product-id"], [receipt objectForKey:@"product_id"]] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorPurchaseInfoDoesNotMatchReceipt userInfo:userInfo];
        }
        
        return NO;
    } else if (![[receipt objectForKey:@"quantity"] isEqual:[purchaseInfo objectForKey:@"quantity"]]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info does not match receipt because purchase info's quantity (%@) does not match receipt's quantity (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"quantity"], [receipt objectForKey:@"quantity"]] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info's quantity (%@) does not match receipt's quantity (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"quantity"], [receipt objectForKey:@"quantity"]] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorPurchaseInfoDoesNotMatchReceipt userInfo:userInfo];
        }
        
        return NO;
    } else if (![[receipt objectForKey:@"item_id"] isEqual:[purchaseInfo objectForKey:@"item-id"]]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info does not match receipt because purchase info's item ID (%@) does not match receipt's item ID (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"item-id"], [receipt objectForKey:@"item_id"]] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info's item ID (%@) does not match receipt's item ID (%@).", @"CargoBay", nil), [purchaseInfo objectForKey:@"item-id"], [receipt objectForKey:@"item_id"]] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorPurchaseInfoDoesNotMatchReceipt userInfo:userInfo];
        }
        
        return NO;
    }

    return YES;
}

BOOL CBValidatePurchaseInfoMatchesReceiptForDevice(NSDictionary *purchaseInfo, NSDictionary *receipt, __unused NSError * __autoreleasing *error) {
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
    if ([[UIDevice currentDevice] respondsToSelector:NSSelectorFromString(@"identifierForVendor")]) {
#if (__IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_5_1)
        NSString *deviceIdentifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        NSString *transactionUniqueVendorIdentifier = [purchaseInfo objectForKey:@"unique-vendor-identifier"];
        NSString *receiptVendorIdentifier = [receipt objectForKey:@"unique_vendor_identifier"];

        if (receiptVendorIdentifier) {
            if (![transactionUniqueVendorIdentifier isEqual:receiptVendorIdentifier] || ![transactionUniqueVendorIdentifier isEqual:deviceIdentifier]) {
#if !TARGET_IPHONE_SIMULATOR
                if (error) {
                    NSDictionary *userInfo = [NSMutableDictionary dictionary];
                    [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info does not match receipt because device's identifier for vendor (%@) does not match purchase info's (%@) and receipt's unique vendor identifier (%@).", @"CargoBay", nil), deviceIdentifier, transactionUniqueVendorIdentifier, receiptVendorIdentifier] forKey:NSLocalizedDescriptionKey];
                    [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Device's identifier for vendor (%@) does not match purchase info's (%@) and receipt's unique vendor identifier (%@).", @"CargoBay", nil), deviceIdentifier, transactionUniqueVendorIdentifier, receiptVendorIdentifier] forKey:NSLocalizedFailureReasonErrorKey];
                    *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorPurchaseInfoDoesNotMatchReceipt userInfo:userInfo];
                }
                
                return NO;
#endif
            }
        }
#endif
    }
#else
#pragma unused (purchaseInfo, receipt)
#endif

    return YES;
}

BOOL CBValidateTransactionMatchesPurchaseInfo(SKPaymentTransaction *transaction, NSDictionary *purchaseInfoDictionary, NSError * __autoreleasing *error) {
    if ((!transaction) || (!purchaseInfoDictionary)) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:NSLocalizedStringFromTable(@"Transaction does not match purchase info because either transaction or purchase info is invalid.", @"CargoBay", nil) forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:NSLocalizedStringFromTable(@"Either transaction or purchase info is invalid.", @"CargoBay", nil) forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        
        return NO;
    }

    NSString *transactionProductIdentifier = transaction.payment.productIdentifier;
    NSString *purchaseInfoDictionaryProductIdentifier = purchaseInfoDictionary[@"product-id"];
    if (![transactionProductIdentifier isEqualToString:purchaseInfoDictionaryProductIdentifier]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction does not match purchase info because transaction's product ID (%@) does not match purchase info's product ID (%@).", @"CargoBay", nil), transactionProductIdentifier, purchaseInfoDictionaryProductIdentifier] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction's product ID (%@) does not match purchase info's product ID (%@).", @"CargoBay", nil), transactionProductIdentifier, purchaseInfoDictionaryProductIdentifier] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        
        return NO;
    }

    NSInteger transactionQuantity = transaction.payment.quantity;
    NSInteger purchaseInfoDictionaryQuantity = [purchaseInfoDictionary[@"quantity"] integerValue];
    if (transactionQuantity != purchaseInfoDictionaryQuantity) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction does not match purchase info because transaction's quantity (%d) does not match purchase info's quantity (%d).", @"CargoBay", nil), transactionQuantity, purchaseInfoDictionaryQuantity] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction's quantity (%d) does not match purchase info's quantity (%d).", @"CargoBay", nil), transactionQuantity, purchaseInfoDictionaryQuantity] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        
        return NO;
    }

    NSString *transactionTransactionIdentifier = transaction.transactionIdentifier;
    NSString *purchaseInfoDictionaryTransactionIdentifier = purchaseInfoDictionary[@"transaction-id"];
    if (![transactionTransactionIdentifier isEqualToString:purchaseInfoDictionaryTransactionIdentifier]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction does not match purchase info because transaction's transaction ID (%@) does not match purchase info's transaction ID (%@).", @"CargoBay", nil), transactionTransactionIdentifier, purchaseInfoDictionaryTransactionIdentifier] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction's transaction ID (%@) does not match purchase info's transaction ID (%@).", @"CargoBay", nil), transactionTransactionIdentifier, purchaseInfoDictionaryTransactionIdentifier] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        
        return NO;
    }

    // Optionally check the bid and bvr match this app's current bundle ID and bundle version.
    NSString *purchaseInfoDictionaryBundleID = purchaseInfoDictionary[@"bid"];
    NSString *appBundleID = [NSBundle mainBundle].bundleIdentifier;
    if (![purchaseInfoDictionaryBundleID isEqualToString:appBundleID]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction does not match purchase info because purchase info's bundle ID (%@) does not match the app bundle ID (%@).", @"CargoBay", nil), purchaseInfoDictionaryBundleID, appBundleID] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info's bundle ID (%@) does not match the app bundle ID (%@).", @"CargoBay", nil), purchaseInfoDictionaryBundleID, appBundleID] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        return NO;
    }

#ifdef _CARGOBAY_VALIDATE_TRANSACTION_BUNDLE_VERSION_
    // Optionally check the bundle version
    // Disable check by default, because it will fail if the app was updated since original purchase
    NSString *purchaseInfoDictionaryBundleVersion = purchaseInfoDictionary[@"bvrs"];
    NSString *appBundleVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:(__bridge NSString *)kCFBundleVersionKey];
    if (![purchaseInfoDictionaryBundleVersion isEqualToString:appBundleVersion]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction does not match purchase info because purchase info's bundle version (%@) does not match the app bundle version (%@).", @"CargoBay", nil), purchaseInfoDictionaryBundleVersion, appBundleVersion] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Purchase info's bundle version (%@) does not match the app bundle version (%@).", @"CargoBay", nil), purchaseInfoDictionaryBundleVersion, appBundleVersion] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        
        return NO;
    }
#endif

    // Optionally check the requestData.
    /*
        `transaction.payment.requestData` is reserved for future use as stated in the document (iOS 6). 
        It is mentioned that the default value will be `nil`. 
        If the value is not `nil`, it will be rejected by the Apple App Store.
      */

    // Optionally check the dates.
    NSDate *transactionDate = transaction.transactionDate;
    NSDate *purchaseInfoDictionaryPurchaseDate = CBDateFromDateString(purchaseInfoDictionary[@"purchase-date"]);

    if (![transactionDate isEqualToDate:purchaseInfoDictionaryPurchaseDate]) {
        if (error) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction does not match purchase info because transaction's transaction date (%@) does not match purchase info's purchase date (%@).", @"CargoBay", nil), transactionDate, purchaseInfoDictionaryPurchaseDate] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction's transaction date (%@) does not match purchase info's purchase date (%@).", @"CargoBay", nil), transactionDate, purchaseInfoDictionaryPurchaseDate] forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionDoesNotMatchesPurchaseInfo userInfo:userInfo];
        }
        
        return NO;
    }

    return YES;
}

#ifdef _SECURITY_SECBASE_H_
    #import <CommonCrypto/CommonDigest.h>
    #import <AssertMacros.h>
#endif

BOOL CBCheckReceiptSecurity(NSString *purchaseInfoString, NSString *signatureString, NSDate *purchaseDate) {
#ifdef _SECURITY_SECBASE_H_
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    BOOL isValid = NO;
    SecCertificateRef leaf = NULL;
    SecCertificateRef intermediate = NULL;
    SecTrustRef trust = NULL;
    SecPolicyRef policy = SecPolicyCreateBasicX509();

    {
        // This scope is required to prevent the compiler from complaining about protected scope
        // FIXME: Intermediate will expires in 2016. See comments below.
        static unsigned int const iTS_intermediate_der_len = 1039;

        static unsigned char const iTS_intermediate_der[] = {
            0x30, 0x82, 0x04, 0x0b, 0x30, 0x82, 0x02, 0xf3, 0xa0, 0x03, 0x02, 0x01,
            0x02, 0x02, 0x01, 0x1a, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
            0xf7, 0x0d, 0x01, 0x01, 0x05, 0x05, 0x00, 0x30, 0x62, 0x31, 0x0b, 0x30,
            0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x13,
            0x30, 0x11, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x13, 0x0a, 0x41, 0x70, 0x70,
            0x6c, 0x65, 0x20, 0x49, 0x6e, 0x63, 0x2e, 0x31, 0x26, 0x30, 0x24, 0x06,
            0x03, 0x55, 0x04, 0x0b, 0x13, 0x1d, 0x41, 0x70, 0x70, 0x6c, 0x65, 0x20,
            0x43, 0x65, 0x72, 0x74, 0x69, 0x66, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f,
            0x6e, 0x20, 0x41, 0x75, 0x74, 0x68, 0x6f, 0x72, 0x69, 0x74, 0x79, 0x31,
            0x16, 0x30, 0x14, 0x06, 0x03, 0x55, 0x04, 0x03, 0x13, 0x0d, 0x41, 0x70,
            0x70, 0x6c, 0x65, 0x20, 0x52, 0x6f, 0x6f, 0x74, 0x20, 0x43, 0x41, 0x30,
            0x1e, 0x17, 0x0d, 0x30, 0x39, 0x30, 0x35, 0x31, 0x39, 0x31, 0x38, 0x33,
            0x31, 0x33, 0x30, 0x5a, 0x17, 0x0d, 0x31, 0x36, 0x30, 0x35, 0x31, 0x38,
            0x31, 0x38, 0x33, 0x31, 0x33, 0x30, 0x5a, 0x30, 0x7f, 0x31, 0x0b, 0x30,
            0x09, 0x06, 0x03, 0x55, 0x04, 0x06, 0x13, 0x02, 0x55, 0x53, 0x31, 0x13,
            0x30, 0x11, 0x06, 0x03, 0x55, 0x04, 0x0a, 0x0c, 0x0a, 0x41, 0x70, 0x70,
            0x6c, 0x65, 0x20, 0x49, 0x6e, 0x63, 0x2e, 0x31, 0x26, 0x30, 0x24, 0x06,
            0x03, 0x55, 0x04, 0x0b, 0x0c, 0x1d, 0x41, 0x70, 0x70, 0x6c, 0x65, 0x20,
            0x43, 0x65, 0x72, 0x74, 0x69, 0x66, 0x69, 0x63, 0x61, 0x74, 0x69, 0x6f,
            0x6e, 0x20, 0x41, 0x75, 0x74, 0x68, 0x6f, 0x72, 0x69, 0x74, 0x79, 0x31,
            0x33, 0x30, 0x31, 0x06, 0x03, 0x55, 0x04, 0x03, 0x0c, 0x2a, 0x41, 0x70,
            0x70, 0x6c, 0x65, 0x20, 0x69, 0x54, 0x75, 0x6e, 0x65, 0x73, 0x20, 0x53,
            0x74, 0x6f, 0x72, 0x65, 0x20, 0x43, 0x65, 0x72, 0x74, 0x69, 0x66, 0x69,
            0x63, 0x61, 0x74, 0x69, 0x6f, 0x6e, 0x20, 0x41, 0x75, 0x74, 0x68, 0x6f,
            0x72, 0x69, 0x74, 0x79, 0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03,
            0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01, 0x0a, 0x02, 0x82, 0x01, 0x01,
            0x00, 0xa4, 0xbc, 0xaf, 0x32, 0x94, 0x43, 0x3e, 0x0b, 0xbc, 0x37, 0x87,
            0xcd, 0x63, 0x89, 0xf2, 0xcc, 0xd9, 0xbe, 0x20, 0x4d, 0x5a, 0xb4, 0xfe,
            0x87, 0x67, 0xd2, 0x9a, 0xde, 0x1a, 0x54, 0x9d, 0xa2, 0xf3, 0xdf, 0x87,
            0xe4, 0x4c, 0xcb, 0x93, 0x11, 0x78, 0xa0, 0x30, 0x8f, 0x34, 0x41, 0xc1,
            0xd3, 0xbe, 0x66, 0x6d, 0x47, 0x6c, 0x98, 0xb8, 0xec, 0x7a, 0xd5, 0xc9,
            0xdd, 0xa5, 0xe4, 0xea, 0xc6, 0x70, 0xf4, 0x35, 0xd0, 0x91, 0xf7, 0xb3,
            0xd8, 0x0a, 0x11, 0x99, 0xab, 0x3a, 0x62, 0x3a, 0xbd, 0x7b, 0xf4, 0x56,
            0x4f, 0xdb, 0x9f, 0x24, 0x93, 0x51, 0x50, 0x7c, 0x20, 0xd5, 0x66, 0x4d,
            0x66, 0xf3, 0x18, 0xa4, 0x13, 0x96, 0x22, 0x16, 0xfd, 0x31, 0xa7, 0xf4,
            0x39, 0x66, 0x9b, 0xfb, 0x62, 0x69, 0x5c, 0x4b, 0x9f, 0x94, 0xa8, 0x4b,
            0xe8, 0xec, 0x5b, 0x64, 0x5a, 0x18, 0x79, 0x8a, 0x16, 0x75, 0x63, 0x42,
            0xa4, 0x49, 0xd9, 0x8c, 0x33, 0xde, 0xad, 0x7b, 0xd6, 0x39, 0x04, 0xf4,
            0xe2, 0x9d, 0x0a, 0x69, 0x8c, 0xeb, 0x4b, 0x12, 0x28, 0x4b, 0x34, 0x48,
            0x07, 0x9b, 0x0e, 0x59, 0xf9, 0x1f, 0x62, 0xb0, 0x03, 0x9f, 0x36, 0xb8,
            0x4e, 0xa3, 0xd3, 0x75, 0x59, 0xd4, 0xf3, 0x3a, 0x05, 0xca, 0xc5, 0x33,
            0x3b, 0xf8, 0xc0, 0x06, 0x09, 0x08, 0x93, 0xdb, 0xe7, 0x4d, 0xbf, 0x11,
            0xf3, 0x52, 0x2c, 0xa5, 0x16, 0x35, 0x15, 0xf3, 0x41, 0x02, 0xcd, 0x02,
            0xd1, 0xfc, 0xf5, 0xf8, 0xc5, 0x84, 0xbd, 0x63, 0x6a, 0x86, 0xd6, 0xb6,
            0x99, 0xf6, 0x86, 0xae, 0x5f, 0xfd, 0x03, 0xd4, 0x28, 0x8a, 0x5a, 0x5d,
            0xaf, 0xbc, 0x65, 0x74, 0xd1, 0xf7, 0x1a, 0xc3, 0x92, 0x08, 0xf4, 0x1c,
            0xad, 0x69, 0xe8, 0x02, 0x4c, 0x0e, 0x95, 0x15, 0x07, 0xbc, 0xbe, 0x6a,
            0x6f, 0xc1, 0xb3, 0xad, 0xa1, 0x02, 0x03, 0x01, 0x00, 0x01, 0xa3, 0x81,
            0xae, 0x30, 0x81, 0xab, 0x30, 0x0e, 0x06, 0x03, 0x55, 0x1d, 0x0f, 0x01,
            0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x01, 0x86, 0x30, 0x0f, 0x06, 0x03,
            0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x05, 0x30, 0x03, 0x01, 0x01,
            0xff, 0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x0e, 0x04, 0x16, 0x04, 0x14,
            0x36, 0x1d, 0xe8, 0xe2, 0x9d, 0x82, 0xd2, 0x01, 0x18, 0xb5, 0x32, 0x6b,
            0x0e, 0xd7, 0x43, 0x0b, 0x91, 0x58, 0x43, 0x3a, 0x30, 0x1f, 0x06, 0x03,
            0x55, 0x1d, 0x23, 0x04, 0x18, 0x30, 0x16, 0x80, 0x14, 0x2b, 0xd0, 0x69,
            0x47, 0x94, 0x76, 0x09, 0xfe, 0xf4, 0x6b, 0x8d, 0x2e, 0x40, 0xa6, 0xf7,
            0x47, 0x4d, 0x7f, 0x08, 0x5e, 0x30, 0x36, 0x06, 0x03, 0x55, 0x1d, 0x1f,
            0x04, 0x2f, 0x30, 0x2d, 0x30, 0x2b, 0xa0, 0x29, 0xa0, 0x27, 0x86, 0x25,
            0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x77, 0x77, 0x77, 0x2e, 0x61,
            0x70, 0x70, 0x6c, 0x65, 0x2e, 0x63, 0x6f, 0x6d, 0x2f, 0x61, 0x70, 0x70,
            0x6c, 0x65, 0x63, 0x61, 0x2f, 0x72, 0x6f, 0x6f, 0x74, 0x2e, 0x63, 0x72,
            0x6c, 0x30, 0x10, 0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64,
            0x06, 0x02, 0x02, 0x04, 0x02, 0x05, 0x00, 0x30, 0x0d, 0x06, 0x09, 0x2a,
            0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x05, 0x05, 0x00, 0x03, 0x82,
            0x01, 0x01, 0x00, 0x75, 0xa6, 0x90, 0xe6, 0x9a, 0xa7, 0xdb, 0x65, 0x70,
            0xa6, 0x09, 0x93, 0x6f, 0x08, 0xdf, 0x2c, 0xdb, 0xe9, 0x28, 0x8d, 0x40,
            0x1b, 0x57, 0x5e, 0xa0, 0xea, 0xf4, 0xec, 0x13, 0x65, 0x1b, 0x71, 0x4a,
            0x4d, 0xdc, 0x80, 0x48, 0x4f, 0xf2, 0xe5, 0xa9, 0xfb, 0x85, 0x6c, 0xb7,
            0x1e, 0x9d, 0xdb, 0xf4, 0x18, 0x48, 0x10, 0x79, 0x17, 0xea, 0xc3, 0x3d,
            0x87, 0xd8, 0xb4, 0x79, 0x6d, 0x14, 0x50, 0xad, 0xd2, 0xbf, 0x3d, 0x4e,
            0xfc, 0x0d, 0xe2, 0xc5, 0x03, 0x94, 0x75, 0x80, 0x73, 0x4d, 0xa5, 0xa1,
            0x91, 0xfe, 0x1c, 0xde, 0x15, 0x17, 0xac, 0x89, 0x71, 0x2a, 0x6f, 0x0f,
            0x67, 0x0a, 0xd3, 0x9c, 0x30, 0xa1, 0x68, 0xfb, 0xcf, 0x70, 0x17, 0xca,
            0xd9, 0x40, 0xfc, 0xf8, 0x1b, 0xbf, 0xce, 0xb0, 0xc4, 0xae, 0xf4, 0x4a,
            0x2d, 0xa9, 0x99, 0x87, 0x06, 0x42, 0x09, 0x86, 0x22, 0x6a, 0x84, 0x40,
            0x39, 0xf4, 0xbb, 0xac, 0x56, 0x18, 0xf7, 0x9a, 0x1c, 0x01, 0x81, 0x5c,
            0x8c, 0x6e, 0x41, 0xf2, 0x5d, 0x19, 0x2c, 0x17, 0x1c, 0x49, 0x46, 0xd9,
            0x1c, 0x7e, 0x93, 0x12, 0x13, 0xc8, 0x67, 0x99, 0xc2, 0xea, 0x83, 0xe3,
            0xa2, 0x8c, 0x0e, 0xb8, 0x3b, 0x2a, 0xdf, 0x1c, 0xbf, 0x4b, 0x8b, 0x6f,
            0x1a, 0xb8, 0xee, 0x97, 0x67, 0x4a, 0xd8, 0xab, 0xaf, 0x8b, 0xa4, 0xda,
            0x5c, 0x87, 0x1e, 0x20, 0xb8, 0xc5, 0xf3, 0xb1, 0xc4, 0x98, 0xa2, 0x37,
            0xf8, 0x9e, 0xc6, 0x9a, 0x6b, 0xa5, 0xad, 0xf6, 0x78, 0x96, 0x0e, 0x82,
            0x8f, 0x04, 0x46, 0x1c, 0xb2, 0xa5, 0xfd, 0x9a, 0x30, 0x51, 0x28, 0xfd,
            0x52, 0x04, 0x15, 0x03, 0xd5, 0x3c, 0xad, 0xfe, 0xf6, 0x78, 0xe0, 0xea,
            0x35, 0xef, 0x65, 0xb5, 0x21, 0x76, 0xdb, 0xa4, 0xef, 0xcb, 0x72, 0xef,
            0x54, 0x6b, 0x01, 0x0d, 0xc7, 0xdd, 0x1a
        };

        __Require([purchaseInfoString canBeConvertedToEncoding:NSASCIIStringEncoding], _out);
        NSData *purchaseInfoData = CBDataFromBase64EncodedString(purchaseInfoString);
        size_t purchaseInfoLength = purchaseInfoData.length;
        uint8_t *purchaseInfoBytes = (uint8_t *)purchaseInfoData.bytes;

        __Require([signatureString canBeConvertedToEncoding:NSASCIIStringEncoding], _out);
        NSData *signatureData = CBDataFromBase64EncodedString(signatureString);
        size_t signatureLength = signatureData.length;
        uint8_t *signatureBytes = (uint8_t *)signatureData.bytes;

        __Require(purchaseInfoBytes && signatureBytes, _out);

        /*
             Binary format looks as follows:

             +-----------------+-----------+------------------+-------------+
             | RECEIPT VERSION | SIGNATURE | CERTIFICATE SIZE | CERTIFICATE |
             +-----------------+-----------+------------------+-------------+
             |          1 byte | 128 bytes |          4 bytes |             |
             +-----------------+-----------+------------------+-------------+
             | big endian                                                   |
             +--------------------------------------------------------------+

             1. Extract receipt version, signature and certificate(s).
             2. Check receipt version == 2.
             3. Sanity check that signature is 128 bytes.
             4. Sanity check certification size <= remaining payload data.
        */

#pragma pack(push, 1)
        struct CBSignatureBlob {
            uint8_t _receiptVersion;
            uint8_t _signature[128];
            uint32_t _certificateLength;
            uint8_t _certificate[];
        } *signatureBlob = (struct CBSignatureBlob *)signatureBytes;
#pragma pack(pop)
        uint32_t certificateLength;

        // Make sure the signature blob is long enough to safely extract the _receiptVersion and _certificateLength fields, then perform a sanity check on the fields.
        __Require(signatureLength > __offsetof(struct CBSignatureBlob, _certificate), _out);
        __Require(signatureBlob->_receiptVersion == 2, _out);
        certificateLength = ntohl(signatureBlob->_certificateLength);
        __Require(signatureLength - __offsetof(struct CBSignatureBlob, _certificate) >= certificateLength, _out);

        // Validate certificate chains back to valid receipt signer; policy approximation for now set intermediate as a trust anchor; current intermediate lapses in 2016.
        NSData *certificateData = [NSData dataWithBytes:signatureBlob->_certificate length:certificateLength];
        __Require(leaf = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData), _out);

        certificateData = [NSData dataWithBytes:iTS_intermediate_der length:iTS_intermediate_der_len];
        __Require(intermediate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData), _out);

        NSArray *anchors = [NSArray arrayWithObject:(__bridge id)intermediate];
        __Require(anchors, _out);

        __Require_noErr(SecTrustCreateWithCertificates(leaf, policy, &trust), _out);
        __Require_noErr(SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)anchors), _out);

        if (purchaseDate) {
            __Require_noErr(SecTrustSetVerifyDate(trust, (__bridge CFDateRef)purchaseDate), _out);
        }

        SecTrustResultType trustResult;
        __Require_noErr(SecTrustEvaluate(trust, &trustResult), _out);
        __Require(trustResult == kSecTrustResultUnspecified, _out);

        __Require(SecTrustGetCertificateCount(trust) == 2, _out);

        // Chain is valid, use leaf key to verify signature on receipt by calculating SHA1(version|purchaseinfo)
        CC_SHA1_CTX SHA1Context;
        uint8_t dataToBeVerified[CC_SHA1_DIGEST_LENGTH];

        CC_SHA1_Init(&SHA1Context);
        CC_SHA1_Update(&SHA1Context, &signatureBlob->_receiptVersion, sizeof(signatureBlob->_receiptVersion));
        CC_SHA1_Update(&SHA1Context, purchaseInfoBytes, (CC_LONG)purchaseInfoLength);
        CC_SHA1_Final(dataToBeVerified, &SHA1Context);

        SecKeyRef receiptSigningKey = SecTrustCopyPublicKey(trust);
        __Require(receiptSigningKey, _out);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-function-declaration"
        __Require_noErr(SecKeyRawVerify(receiptSigningKey, kSecPaddingPKCS1SHA1, dataToBeVerified, sizeof(dataToBeVerified), signatureBlob->_signature, sizeof(signatureBlob->_signature)), _out);
#pragma clang diagnostic pop

        // TODO: Implements optional verification step.
        // Optional: Verify that the receipt certificate has the 1.2.840.113635.100.6.5.1 Null OID.
        // The signature is a 1024-bit RSA signature.

        isValid = YES;
    }
    
_out:
    if (leaf) {
        CFRelease(leaf);
    }
    
    if (intermediate) {
        CFRelease(intermediate);
    }
    
    if (trust) {
        CFRelease(trust);
    }
    
    if (policy) {
        CFRelease(policy);
    }

    return isValid;
#pragma clang diagnostic pop
#else
    return YES;
#endif
}

#pragma mark -

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
NSData * CBTransactionReceiptFromPaymentTransaction(SKPaymentTransaction *transaction) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // if ([NSBundle instancesRespondToSelector:@selector(appStoreReceiptURL)]) {
    //     NSError *error = nil;
    //     NSData *data = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] appStoreReceiptURL] options:0 error:&error];
    //     if (data && !error) {
    //         return data;
    //     }
    // }

    return transaction.transactionReceipt;
#pragma clang diagnostic pop
}
#endif

NSDictionary * CBPurchaseInfoFromTransactionReceipt(NSData *transactionReceiptData, NSError * __autoreleasing *error) {
    NSDictionary *transactionReceiptDictionary = [NSPropertyListSerialization propertyListWithData:transactionReceiptData options:NSPropertyListImmutable format:nil error:error];
    if (!transactionReceiptDictionary || ![transactionReceiptDictionary respondsToSelector:@selector(objectForKey:)]) {
        return nil;
    }

    NSString *purchaseInfo = [transactionReceiptDictionary objectForKey:@"purchase-info"];
    NSDictionary *purchaseInfoDictionary = [NSPropertyListSerialization propertyListWithData:CBDataFromBase64EncodedString(purchaseInfo) options:NSPropertyListImmutable format:nil error:error];
    if (!purchaseInfoDictionary) {
        return nil;
    }
    
    NSString *signature = [transactionReceiptDictionary objectForKey:@"signature"];
    NSDate *purchaseDate = CBDateFromDateString([purchaseInfoDictionary objectForKey:@"purchase-date"]);
    
    if (!CBCheckReceiptSecurity(purchaseInfo, signature, purchaseDate)) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:NSLocalizedStringFromTable(@"Cannot extract purchase info from transaction receipt because purchase info failed to validate against its signature.", @"CargoBay", nil) forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:NSLocalizedStringFromTable(@"Purchase info failed to validate against its signature.", @"CargoBay", nil) forKey:NSLocalizedFailureReasonErrorKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorCannotExtractPurchaseInfoFromTransactionReceipt userInfo:userInfo];
        }
        
        return nil;
    }

    return purchaseInfoDictionary;
}

#pragma mark

@interface CargoBayProductRequestDelegate : NSObject <SKRequestDelegate, SKProductsRequestDelegate>
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueProductSuccessBlock success;
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueProductFailureBlock failure;

+ (void)registerDelegate:(CargoBayProductRequestDelegate *)delegate;
+ (void)unregisterDelegate:(CargoBayProductRequestDelegate *)delegate;

- (id)initWithSuccess:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
              failure:(void (^)(NSError *error))failure;
@end

#pragma mark -

@interface CargoBay ()
@property (readwrite, nonatomic, strong) NSOperationQueue *requestOperationQueue;
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueTransactionsBlock paymentQueueTransactionsUpdated;
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueTransactionsBlock paymentQueueTransactionsRemoved;
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueRestoreSuccessBlock paymentQueueRestoreSuccess;
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueRestoreFailureBlock paymentQueueRestoreFailure;
@property (readwrite, nonatomic, copy) CargoBayPaymentQueueUpdatedDownloadsBlock paymentQueueUpdatedDownloads;
@property (readwrite, nonatomic, copy) CargoBayTransactionIDUniquenessVerificationBlock transactionIDUniquenessVerificationBlock;
@end

@implementation CargoBay

+ (instancetype)sharedManager {
    static id _sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[self alloc] init];
    });

    return _sharedManager;
}

+ (AFHTTPRequestOperationManager *)receiptVerificationOperationManagerWithBaseURL:(NSURL *)baseURL {
    AFHTTPRequestOperationManager *manager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseURL];
    
    manager.requestSerializer  = [AFJSONRequestSerializer serializer];
    [manager.requestSerializer setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    manager.responseSerializer.acceptableContentTypes = [manager.responseSerializer.acceptableContentTypes setByAddingObject:@"text/plain"];
    
    return manager;
}

- (id)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    self.requestOperationQueue = [[NSOperationQueue alloc] init];

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

- (void)productsWithRequest:(NSURLRequest *)urlRequest
                    success:(void (^)(NSArray *products, NSArray *invalidIdentifiers))success
                    failure:(void (^)(NSError *error))failure
{
    AFHTTPRequestOperation *requestOperation = [[AFHTTPRequestOperation alloc] initWithRequest:urlRequest];
    requestOperation.responseSerializer = [AFJSONResponseSerializer serializer];
    [requestOperation setCompletionBlockWithSuccess:^(__unused AFHTTPRequestOperation *operation, id JSON) {
        if (JSON && [JSON isKindOfClass:[NSArray class]]) {
            [self productsWithIdentifiers:[NSSet setWithArray:JSON] success:success failure:failure];
        } else {
            if (failure) {
                NSDictionary *userInfo = [NSMutableDictionary dictionary];
                [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Expected array of product identifiers, got %@.", @"CargoBay", nil), JSON] forKey:NSLocalizedDescriptionKey];
                NSError *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionNotInPurchasedOrRestoredState userInfo:userInfo];
                
                failure(error);
            }
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(error);
        }
    }];
    
    [self.requestOperationQueue addOperation:requestOperation];
}

- (void)verifyTransaction:(SKPaymentTransaction *)transaction
                 password:(NSString *)passwordOrNil
                  success:(void (^)(NSDictionary *responseObject))success
                  failure:(void (^)(NSError *error))failure
{
    if ((transaction.transactionState != SKPaymentTransactionStatePurchased) && (transaction.transactionState != SKPaymentTransactionStateRestored)) {
        if (failure) {
            NSDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Cannot verify transaction because transaction (%@) not in purchased or restored state.", @"CargoBay", nil), transaction.transactionIdentifier] forKey:NSLocalizedDescriptionKey];
            [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction (%@) not in purchased or restored state.", @"CargoBay", nil), transaction.transactionIdentifier] forKey:NSLocalizedFailureReasonErrorKey];
            NSError *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionNotInPurchasedOrRestoredState userInfo:userInfo];

            failure(error);
        }
        return;
    }

    NSError *error = nil;
    if (![self isValidTransaction:transaction error:&error]) {
        if (failure) {
            failure(error);
        }

        return;
    }

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
    [self verifyTransactionReceipt:CBTransactionReceiptFromPaymentTransaction(transaction) password:passwordOrNil success:success failure:failure];
#else
#pragma unused (passwordOrNil, success)
#endif
}

- (void)setTransactionIDUniquenessVerificationWithBlock:(BOOL (^)(NSString *transactionID))block {
    _transactionIDUniquenessVerificationBlock = [block copy];
}

- (void)verifyTransactionReceipt:(NSData *)transactionReceipt
                        password:(NSString *)passwordOrNil
                         success:(void (^)(NSDictionary *responseObject))success
                         failure:(void (^)(NSError *error))failure
{
    NSError *error = nil;
    NSDictionary *receiptDictionary = [NSPropertyListSerialization propertyListWithData:transactionReceipt options:NSPropertyListImmutable format:nil error:&error];
    if (!receiptDictionary) {
        if (failure) {
            failure(error);
        }
        return;
    }

    NSString *environment = [receiptDictionary objectForKey:@"environment"];
    NSURL *endpoint = [environment isEqual:@"Sandbox"] ? [NSURL URLWithString:kCargoBaySandboxReceiptVerificationURLString] : [NSURL URLWithString:kCargoBayProductionReceiptVerificationURLString];

    [self verifyTransactionWithMethod:@"POST" endpoint:endpoint receipt:transactionReceipt password:passwordOrNil success:success failure:failure];
}

- (void)verifyTransactionWithMethod:(NSString *)method
                           endpoint:(NSURL *)url
                            receipt:(NSData *)transactionReceipt
                           password:(NSString *)password
                            success:(void (^)(NSDictionary *responseObject))success
                            failure:(void (^)(NSError *error))failure
{
    NSURL *baseURL = [NSURL URLWithString:[[url absoluteString] substringToIndex:[[url absoluteString] rangeOfString:[url path] options:NSBackwardsSearch].location]];
    AFHTTPRequestOperationManager *manager = [[self class] receiptVerificationOperationManagerWithBaseURL:baseURL];

    NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithObject:CBBase64EncodedStringFromData(transactionReceipt) forKey:@"receipt-data"];
    if (password) {
        [parameters setObject:password forKey:@"password"];
    }

    NSURLRequest *request = [manager.requestSerializer requestWithMethod:method URLString:url.absoluteString parameters:parameters error:nil];
    AFHTTPRequestOperation *requestOperation = [manager HTTPRequestOperationWithRequest:request success:^(__unused AFHTTPRequestOperation *operation, id responseObject) {
        NSInteger status = [responseObject valueForKey:@"status"] ? [[responseObject valueForKey:@"status"] integerValue] : NSNotFound;

        switch (status) {
            case CargoBayStatusOK:
            case CargoBayStatusReceiptValidButSubscriptionExpired: {
                NSDictionary *receipt = [responseObject valueForKey:@"receipt"];
                NSError *error = nil;

                NSDictionary *purchaseInfo = CBPurchaseInfoFromTransactionReceipt(transactionReceipt, &error);
                if (!purchaseInfo) {
                    if (failure) {
                        failure(error);
                    }
                    
                    return;
                }

                BOOL isValid = CBValidatePurchaseInfoMatchesReceipt(purchaseInfo, receipt, &error);
                if (!isValid) {
                    if (failure) {
                        failure(error);
                    }
                    
                    return;
                }
                
                // Every (re-)installation generates a new unique identifier for vendor.
                // Every purchase and restoration receipt will be tagged with this new unique identifier.
                // However, the latest receipt info might have a unique identifier for vendor from another device, from a previous installation, etc.
                // Therefore, we should only check if the purchase info matches receipt for device for receipt we restored with this device.
                isValid = CBValidatePurchaseInfoMatchesReceiptForDevice(purchaseInfo, receipt, &error);
                if (!isValid) {
                    if (failure) {
                        failure(error);
                    }
                    
                    return;
                }

                NSString *latestBase64EncodedTransactionReceipt = [responseObject valueForKey:@"latest_receipt"];
                NSDictionary *latestReceipt = [responseObject valueForKey:@"latest_receipt_info"];
                if ((latestBase64EncodedTransactionReceipt) && (latestReceipt)) {
                    NSData *latestTransactionReceipt = CBDataFromBase64EncodedString(latestBase64EncodedTransactionReceipt);
                    NSDictionary *latestPurchaseInfo = CBPurchaseInfoFromTransactionReceipt(latestTransactionReceipt, &error);
                    if (!latestPurchaseInfo) {
                        if (failure) {
                            failure(error);
                        }
                        
                        return;
                    }

                    BOOL isLatestValid = CBValidatePurchaseInfoMatchesReceipt(latestPurchaseInfo, latestReceipt, &error);
                    if (!isLatestValid) {
                        if (failure) {
                            failure(error);
                        }
                        return;
                    }

                    if (success) {
                        success(responseObject);
                    }
                } else if ((latestBase64EncodedTransactionReceipt) || (latestReceipt)) {
                    if (failure) {
                        failure(error);
                    }
                } else {
                    if (success) {
                        success(responseObject);
                    }
                }

                break;
            }
            case CargoBayStatusSandboxReceiptSentToProduction:
                [self verifyTransactionWithMethod:@"POST" endpoint:[NSURL URLWithString:kCargoBaySandboxReceiptVerificationURLString] receipt:transactionReceipt password:password success:success failure:failure];
                break;
            case CargoBayStatusProductionReceiptSentToSandbox:
                [self verifyTransactionWithMethod:@"POST" endpoint:[NSURL URLWithString:kCargoBayProductionReceiptVerificationURLString] receipt:transactionReceipt password:password success:success failure:failure];
                break;
            default:
                if (failure) {
                    NSString *exception = [responseObject valueForKey:@"exception"];
                    NSDictionary *userInfo = exception ? [NSDictionary dictionaryWithObject:exception forKey:NSLocalizedFailureReasonErrorKey] : nil;
                    NSError *error = [[NSError alloc] initWithDomain:CargoBayErrorDomain code:status userInfo:userInfo];
                    
                    failure(error);
                }
                break;
        }
    } failure:^(__unused AFHTTPRequestOperation *operation, NSError *error) {
        if (failure) {
            failure(error);
        }
    }];

    [requestOperation setWillSendRequestForAuthenticationChallengeBlock:^(__unused NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
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

    [self.requestOperationQueue addOperation:requestOperation];
}

- (void)setPaymentQueueUpdatedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block {
    self.paymentQueueTransactionsUpdated = block;
}

- (void)setPaymentQueueRemovedTransactionsBlock:(void (^)(SKPaymentQueue *queue, NSArray *transactions))block {
    self.paymentQueueTransactionsRemoved = block;
}

- (void)setPaymentQueueRestoreCompletedTransactionsWithSuccess:(void (^)(SKPaymentQueue *queue))success
                                                       failure:(void (^)(SKPaymentQueue *queue, NSError *error))failure
{
    self.paymentQueueRestoreSuccess = success;
    self.paymentQueueRestoreFailure = failure;
}

- (void)setPaymentQueueUpdatedDownloadsBlock:(void (^)(SKPaymentQueue *queue, NSArray *downloads))block {
    self.paymentQueueUpdatedDownloads = block;
}

#pragma mark - Receipt Verification

- (BOOL)isValidTransaction:(SKPaymentTransaction *)transaction
                     error:(NSError * __autoreleasing *)error
{
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
    if (!(transaction && CBTransactionReceiptFromPaymentTransaction(transaction))) {
        if (error) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
            [userInfo setValue:NSLocalizedStringFromTable(@"Transaction object is not valid.", @"CargoBay", nil) forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionNotValid userInfo:userInfo];
        }
        
        return NO;
    }

    NSData *transactionReceipt = CBTransactionReceiptFromPaymentTransaction(transaction);
    NSDictionary *purchaseInfoDictionary = CBPurchaseInfoFromTransactionReceipt(transactionReceipt, error);
    if (!purchaseInfoDictionary) {
        return NO;
    }

    if (!CBValidateTransactionMatchesPurchaseInfo(transaction, purchaseInfoDictionary, error)) {
        return NO;
    }

    NSString *transactionID = [purchaseInfoDictionary objectForKey:@"transaction-id"];
    if (self.transactionIDUniquenessVerificationBlock) {
        if (!self.transactionIDUniquenessVerificationBlock(transactionID)) {
            if (error) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction ID (%@) is not unique.", @"CargoBay", nil), transactionID] forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionIDNotUnique userInfo:userInfo];
            }
            
            return NO;
        }
    } else {
        NSMutableDictionary *knownIAPTransactionsDictionary = [[[NSUserDefaults standardUserDefaults] objectForKey:kCargoBayKnownIAPTransactionsKey] mutableCopy];
        if (!knownIAPTransactionsDictionary) {
            knownIAPTransactionsDictionary = [NSMutableDictionary dictionary];
        }

        if (![knownIAPTransactionsDictionary objectForKey:transactionID]) {
            [knownIAPTransactionsDictionary setObject:[NSNumber numberWithBool:YES] forKey:transactionID];

            [[NSUserDefaults standardUserDefaults] setObject:knownIAPTransactionsDictionary forKey:kCargoBayKnownIAPTransactionsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];

            return YES;
        } else {
            if (error) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
                [userInfo setValue:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Transaction ID (%@) is not unique.", @"CargoBay", nil), transactionID] forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:CargoBayErrorDomain code:CargoBayErrorTransactionIDNotUnique userInfo:userInfo];
            }

            return NO;
        }        
    }
#else
#pragma unused (transaction, error)
#endif

    return YES;
}

#pragma mark - SKPaymentTransactionObserver

- (void)paymentQueue:(SKPaymentQueue *)queue
    updatedDownloads:(NSArray *)downloads
{
    if (self.paymentQueueUpdatedDownloads) {
        self.paymentQueueUpdatedDownloads(queue, downloads);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    if (self.paymentQueueTransactionsUpdated) {
        self.paymentQueueTransactionsUpdated(queue, transactions);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 removedTransactions:(NSArray *)transactions
{
    if (self.paymentQueueTransactionsRemoved) {
        self.paymentQueueTransactionsRemoved(queue, transactions);
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    if (self.paymentQueueRestoreSuccess) {
        self.paymentQueueRestoreSuccess(queue);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    if (self.paymentQueueRestoreFailure) {
        self.paymentQueueRestoreFailure(queue, error);
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

    self.success = success;
    self.failure = failure;

    return self;
}

#pragma mark - SKRequestDelegate

- (void)request:(SKRequest *)request
didFailWithError:(NSError *)error
{
    if (self.failure) {
        self.failure(error);
    }

    request.delegate = nil;
    [[self class] unregisterDelegate:self];
}

- (void)requestDidFinish:(SKRequest *)request {
    request.delegate = nil;
    [[self class] unregisterDelegate:self];
}

#pragma mark - SKProductsRequestDelegate

- (void)productsRequest:(__unused SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    if (self.success) {
        self.success(response.products, response.invalidProductIdentifiers);
    }
}

@end
