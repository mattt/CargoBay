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

__unused static NSString * const kCargoBaySandboxReceiptVerificationBaseURLString = @"https://sandbox.itunes.apple.com/";
static NSString * const kCargoBayProductionReceiptVerificationBaseURLString = @"https://buy.itunes.apple.com/";

typedef void (^CargoBayPaymentQueueProductSuccessBlock)(NSArray *products, NSArray *invalidIdentifiers);
typedef void (^CargoBayPaymentQueueProductFailureBlock)(NSError *error);
typedef void (^CargoBayPaymentQueueTransactionsBlock)(SKPaymentQueue *queue, NSArray *transactions);
typedef void (^CargoBayPaymentQueueRestoreSuccessBlock)(SKPaymentQueue *queue);
typedef void (^CargoBayPaymentQueueRestoreFailureBlock)(SKPaymentQueue *queue, NSError *error);

#pragma mark - Serializations

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

static NSData *CBDataFromBase64EncodedString(NSString *theBase64EncodedString) {
    NSData *theData = [theBase64EncodedString dataUsingEncoding:NSASCIIStringEncoding];
    uint8_t *theInput = (uint8_t *)theData.bytes;
    NSUInteger theLength = theData.length;
    
    NSUInteger theOutputLength = ((theLength + 3) / 4) * 3;
    if (theInput[theLength - 1] == 61) {
        if (theInput[theLength - 2] == 61) {
            theOutputLength -= 2;
        } else {
            theOutputLength -= 1;
        }
    }
    
    NSMutableData *theBase64DecodedData = [NSMutableData dataWithLength:theOutputLength];
    
    uint8_t *theOutput = (uint8_t *)theBase64DecodedData.mutableBytes;
    
    // Reference http://cocoawithlove.com/2009/06/base64-encoding-options-on-mac-and.html
    // Our algorithm, which is derived from mattt's base 64 encoding and uses Matt Gallagher
    // base 64 decoding table, uses 0 instead of xx (either 'A' or masked-out area) as it won't
    // cause any side effects. :)
    static uint8_t const theBase64DecodingTable[256] = {
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
    
    for (NSUInteger theIndex = 0; theIndex < theLength; theIndex += 4) {
        NSUInteger theValue = 0;
        for (NSUInteger theOtherIndex = 0; theOtherIndex < (theIndex + 4); theOtherIndex++) {
            theValue <<= 6;
            if (theOtherIndex < theLength) {
                theValue |= (0x3F & theBase64DecodingTable[theInput[theOtherIndex]]);
            }
        }
        
        NSUInteger theOutputIndex = (theIndex / 4) * 3;
        theOutput[theOutputIndex + 0] = (theValue >> 16) & 0xFF;
        theOutput[theOutputIndex + 1] = (theValue >> 8) & 0xFF;
        theOutput[theOutputIndex + 2] = (theValue >> 0) & 0xFF;
    }
    
    return [NSData dataWithData:theBase64DecodedData];
}

#pragma mark - Validations

static BOOL CBValidateTrust(SecTrustRef trust, NSError * __autoreleasing *error) {
#ifdef _SECURITY_SECBASE_H_
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
    
    if (trust) {
        if (!trusted && error) {
            *error = [NSError errorWithDomain:@"kSecTrustError" code:(NSInteger)result userInfo:nil];
        }
        return trusted;
    }

    return NO;
#else
    return YES;
#endif
}

static BOOL CBValidateTransactionMatchesReceipt(SKPaymentTransaction *transaction, NSDictionary *receipt, NSError * __autoreleasing *error) {
    NSDictionary *transactionReceipt = [NSPropertyListSerialization propertyListWithData:transaction.transactionReceipt options:NSPropertyListImmutable format:nil error:error];
    if (!transactionReceipt) {
        return NO;
    }
        
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

#pragma mark - Check Receipt Signature

#ifdef _SECURITY_SECBASE_H_
#include <CommonCrypto/CommonDigest.h>
//#include <Security/Security.h>
#include <AssertMacros.h>
#endif

static BOOL CBCheckReceiptSecurity(NSString *thePurchaseInfoString, NSString *theSignatureString, CFDateRef thePurchaseDate) {
#ifdef _SECURITY_SECBASE_H_
    BOOL isValid = NO;
    SecCertificateRef theLeaf = NULL;
    SecCertificateRef theIntermediate = NULL;
    SecTrustRef theTrust = NULL;
    SecPolicyRef thePolicy = SecPolicyCreateBasicX509();
    
    { // This scope is required to prevent the compiler from complaining about protected scope
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
    
    NSData *theCertificateData;
    NSArray *theAnchors;
    
    /*
     Parse inputs:
     thePurchaseInfoString and theSignatureString are base64 encoded JSON blobs that need to
     be decoded.
     */
    require([thePurchaseInfoString canBeConvertedToEncoding:NSASCIIStringEncoding] &&
            [theSignatureString canBeConvertedToEncoding:NSASCIIStringEncoding], theOutLabel);
    
    NSData *thePurchaseInfoData = CBDataFromBase64EncodedString(thePurchaseInfoString);
    size_t thePurchaseInfoLength = thePurchaseInfoData.length;
    uint8_t *thePurchaseInfoBytes = (uint8_t *)thePurchaseInfoData.bytes;
    
    NSData *theSignatureData = CBDataFromBase64EncodedString(theSignatureString);
    size_t theSignatureLength = theSignatureData.length;
    uint8_t *theSignatureBytes = (uint8_t *)theSignatureData.bytes;
    
    require(thePurchaseInfoBytes && theSignatureBytes, theOutLabel);
    
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
    } *theSignatureBlobPtr = (struct CBSignatureBlob *)theSignatureBytes;
#pragma pack(pop)
    uint32_t theCertificateLength;
    
    /*
     Make sure the signature blob is long enough to safely extract the _receiptVersion and
     _certificateLength fields, then perform a sanity check on the fields.
     */
    require(theSignatureLength > offsetof(struct CBSignatureBlob, _certificate), theOutLabel);
    require(theSignatureBlobPtr->_receiptVersion == 2, theOutLabel);
    theCertificateLength = ntohl(theSignatureBlobPtr->_certificateLength);
    require(theSignatureLength - offsetof(struct CBSignatureBlob, _certificate) >= theCertificateLength, theOutLabel);
    
    /*
     Validate certificate chains back to valid receipt signer; policy approximation for now
     set intermediate as a trust anchor; current intermediate lapses in 2016.
     */
    theCertificateData = [NSData dataWithBytes:theSignatureBlobPtr->_certificate length:theCertificateLength];
    require(theLeaf = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)theCertificateData), theOutLabel);
    
    theCertificateData = [NSData dataWithBytes:iTS_intermediate_der length:iTS_intermediate_der_len];
    require(theIntermediate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)theCertificateData), theOutLabel);
    
    theAnchors = @[ (__bridge id)theIntermediate ];
    require(theAnchors, theOutLabel);
    
    require_noerr(SecTrustCreateWithCertificates(theLeaf, thePolicy, &theTrust), theOutLabel);
    require_noerr(SecTrustSetAnchorCertificates(theTrust, (__bridge CFArrayRef)theAnchors), theOutLabel);
    
    if (thePurchaseDate) {
        require_noerr(SecTrustSetVerifyDate(theTrust, thePurchaseDate), theOutLabel);
    }
    
    SecTrustResultType theTrustResult;
    require_noerr(SecTrustEvaluate(theTrust, &theTrustResult), theOutLabel);
    require(theTrustResult == kSecTrustResultUnspecified, theOutLabel);
    
    require(2 == SecTrustGetCertificateCount(theTrust), theOutLabel);
    
    /*
     Chain is valid, use leaf key to verify signature on receipt by
     calculating SHA1(version|purchaseinfo)
     */
    
    CC_SHA1_CTX theSHA1Context;
    uint8_t theDataToBeVerified[CC_SHA1_DIGEST_LENGTH];
    
    CC_SHA1_Init(&theSHA1Context);
    CC_SHA1_Update(&theSHA1Context, &theSignatureBlobPtr->_receiptVersion, sizeof(theSignatureBlobPtr->_receiptVersion));
    CC_SHA1_Update(&theSHA1Context, thePurchaseInfoBytes, thePurchaseInfoLength);
    CC_SHA1_Final(theDataToBeVerified, &theSHA1Context);
    
    SecKeyRef theReceiptSigningKey = SecTrustCopyPublicKey(theTrust);
    require(theReceiptSigningKey, theOutLabel);
    require_noerr(SecKeyRawVerify(theReceiptSigningKey, kSecPaddingPKCS1SHA1, theDataToBeVerified, sizeof(theDataToBeVerified), theSignatureBlobPtr->_signature, sizeof(theSignatureBlobPtr->_signature)), theOutLabel);
    
    // TODO: Implements optional verification step.
    /*
     Optional: Verify that the receipt certificate has the 1.2.840.113635.100.6.5.1 Null OID
     
     The signature is a 1024-bit RSA signature.
     */
    
    isValid = YES;
    }
theOutLabel:
    if (theLeaf) {
        CFRelease(theLeaf);
    }
    if (theIntermediate) {
        CFRelease(theIntermediate);
    }
    if (theTrust) {
        CFRelease(theTrust);
    }
    if (thePolicy) {
        CFRelease(thePolicy);
    }
    
    return isValid;
#else
    return YES;
#endif
}

#pragma mark

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
    
    _receiptVerificationClient = [[AFHTTPClient alloc] initWithBaseURL:[NSURL URLWithString:kCargoBayProductionReceiptVerificationBaseURLString]];
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
    NSError *error = nil;
    if (![self verifyPurchase:transaction error:&error]) {
        if (failure) {
            if (!error) {
                error = [[NSError alloc] initWithDomain:SKErrorDomain code:-1 userInfo:nil];
            }
            failure(error);
        }
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

#pragma mark - Receipt Verification

// This method should be called once a transaction gets to the SKPaymentTransactionStatePurchased or SKPaymentTransactionStateRestored state
// Call it with the SKPaymentTransaction.transactionReceipt
- (BOOL)verifyPurchase:(SKPaymentTransaction *)theTransaction error:(NSError * __autoreleasing *)theError {
    BOOL isOK = [self isTransactionAndItsReceiptValid:theTransaction error:theError];
    if (isOK) {
        // The transaction looks ok, so start the verify process.
        return YES;
    } else {
        // There was something wrong with the transaction we got back, so no need to call verifyReceipt.
        return NO;
    }
}

// Check the validity of the receipt.
- (BOOL)isTransactionAndItsReceiptValid:(SKPaymentTransaction *)theTransaction error:(NSError * __autoreleasing *)theError {
    if (!((theTransaction) && (theTransaction.transactionReceipt) && (theTransaction.transactionReceipt.length > 0))) {
        // Transaction is not valid.
        return NO;
    }
    
    // Pull the purchase-info out of the transaction receipt, decode it, and save it for later so
    // it can be cross checked with the verifyReceipt.
    NSDictionary *theReceiptDictionary = [NSPropertyListSerialization propertyListWithData:theTransaction.transactionReceipt options:NSPropertyListImmutable format:nil error:theError];
    if (!theReceiptDictionary) {
        return NO;
    }
    NSString *theTransactionPurchaseInfo = [theReceiptDictionary objectForKey:@"purchase-info"];
    NSDictionary *thePurchaseInfoDictionary = [NSPropertyListSerialization propertyListWithData:CBDataFromBase64EncodedString(theTransactionPurchaseInfo) options:NSPropertyListImmutable format:nil error:theError];
    if (!thePurchaseInfoDictionary) {
        return NO;
    }
    __unused NSString *theTransactionID = [thePurchaseInfoDictionary objectForKey:@"transaction-id"];
    NSString *thePurchaseDateString = [thePurchaseInfoDictionary objectForKey:@"purchase-date"];
    NSString *theSignature = [theReceiptDictionary objectForKey:@"signature"];
    
    // Converts the string into a date
    NSDateFormatter *theDateFormatter =  [[NSDateFormatter alloc] init];
    theDateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss z";
    
    NSDate *thePurchaseDate = [theDateFormatter dateFromString:[thePurchaseDateString stringByReplacingOccurrencesOfString:@"Etc/" withString:@""]];
    
    // In Apple's implementation, it stores the transaction ID together with its receipt.
    // Apple chooses the `NSUserDefaults` for storage. I'm not sure about whether we should
    // do the same (Any security concern?) or should we roll a delegate system and implements
    // a default implementation that mimic Apple's one. I am more supportive of the latter.
    // The TODOs below is written as a reminder that this portion of the code is still in review.
    
//    // TODO: Checks to see if the transaction ID is unique.
//    if (![self isTransactionIDUnique:theTransactionID]) {
//        // We've seen this transaction before.
//        // Had [self.transactionsReceiptStorageDictionary objectForKey:theTransactionID];
//        // Got thePurchaseInfoDictionary
//        return NO;
//    }
    
    // Check the authenticity of the receipt response/signature etc.
    
    BOOL theResult = CBCheckReceiptSecurity(theTransactionPurchaseInfo, theSignature, (__bridge CFDateRef)thePurchaseDate);
    
    if (!theResult) {
        return NO;
    }
    
    // Ensure the transaction itself is legit
    if (![self doTransactionDetailsMatchPurchaseInfo:theTransaction withPurchaseInfo:thePurchaseInfoDictionary]) {
        return NO;
    }
    
//    // TODO: Make a note of the fact that we've seen the transaction id already
//    [self saveTransactionID:theTransactionID];
    
    return YES;
}

// Make sure the transaction details actually match the purchase info
- (BOOL)doTransactionDetailsMatchPurchaseInfo:(SKPaymentTransaction *)theTransaction withPurchaseInfo:(NSDictionary *)thePurchaseInfoDictionary {
    if ((!theTransaction) || (!thePurchaseInfoDictionary)) {
        return NO;
    }
    
    NSInteger theFailCount = 0;
    
    {
        NSString *theTransactionProductIdentifier = theTransaction.payment.productIdentifier;
        NSString *thePurchaseInfoDictionaryProductIdentifier = thePurchaseInfoDictionary[@"product-id"];
        if (![theTransactionProductIdentifier isEqualToString:thePurchaseInfoDictionaryProductIdentifier]) {
            theFailCount++;
        }
    }
    
    {
        NSInteger theTransactionQuantity = theTransaction.payment.quantity;
        NSInteger thePurchaseInfoDictionaryQuantity = [thePurchaseInfoDictionary[@"quantity"] integerValue];
        if (theTransactionQuantity != thePurchaseInfoDictionaryQuantity) {
            theFailCount++;
        }
    }
    
    {
        NSString *theTransactionTransactionIdentifier = theTransaction.transactionIdentifier;
        NSString *thePurchaseInfoDictionaryTransactionIdentifier = thePurchaseInfoDictionary[@"transaction-id"];
        if (![theTransactionTransactionIdentifier isEqualToString:thePurchaseInfoDictionaryTransactionIdentifier]) {
            theFailCount++;
        }
    }
    
    // Optionally check the bid and bvr match this app's current bundle ID and bundle version.
    {
        NSString *thePurchaseInfoDictionaryBundleID = thePurchaseInfoDictionary[@"bid"];
        NSString *theAppBundleID = [NSBundle mainBundle].bundleIdentifier;
        if (![thePurchaseInfoDictionaryBundleID isEqualToString:theAppBundleID]) {
            theFailCount++;
        }
    }
    
    {
        NSString *thePurchaseInfoDictionaryBundleVersion = thePurchaseInfoDictionary[@"bvrs"];
        NSString *theAppBundleVersion = [NSBundle mainBundle].infoDictionary[(__bridge NSString *)kCFBundleVersionKey];
        if (![thePurchaseInfoDictionaryBundleVersion isEqualToString:theAppBundleVersion]) {
            theFailCount++;
        }
    }
    
    // Optionally check the requestData.
    {
        // `theTransaction.payment.requestData` is reserved for future use as stated
        // in the document (iOS 6). It is mentioned that the default value will be nil.
        // If the value is not nil, it will be rejected by the Apple App Store.
        // We could check for nil. But Apple might decides to populate this field
        // in the future, which will break our code by then. So I think the wisest
        // choice would be to avoid doing anything to this field all together for now.
    }
    
    // Optionally check the dates.
    {
        NSDate *theTransactionTransactionDate = theTransaction.transactionDate;
        NSString *thePurchaseInfoDictionaryPurchaseDateString = thePurchaseInfoDictionary[@"purchase-date"];
        // Converts the string into a date
        NSDateFormatter *theDateFormatter =  [[NSDateFormatter alloc] init];
        theDateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss z";
        
        NSDate *thePurchaseInfoDictionaryPurchaseDate = [theDateFormatter dateFromString:[thePurchaseInfoDictionaryPurchaseDateString stringByReplacingOccurrencesOfString:@"Etc/" withString:@""]];
        
        if (![theTransactionTransactionDate isEqualToDate:thePurchaseInfoDictionaryPurchaseDate]) {
            theFailCount++;
        }
    }
    
    if (theFailCount != 0) {
        return NO;
    }
    
    // The transaction and its signed content seem ok.
    return YES;
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
