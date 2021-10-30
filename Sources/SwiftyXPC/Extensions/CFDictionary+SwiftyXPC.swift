//
//  CFDictionary+SwiftyXPC.swift
//  SwiftyXPC
//
//  Created by Charles Srstka on 7/22/21.
//

import CoreFoundation
import XPC

extension CFDictionary {
    public subscript(key: String) -> CFTypeRef? {
        self[CFString.fromString(key)]
    }

    public subscript<T: CFTypeRef>(key: String, as typeID: CFTypeID) -> T? {
        self[CFString.fromString(key), as: typeID]
    }

    public subscript(key: CFTypeRef) -> CFTypeRef? {
        return unsafeBitCast(
            CFDictionaryGetValue(self, unsafeBitCast(key, to: UnsafeRawPointer.self)),
            to: CFTypeRef?.self
        )
    }

    public subscript<T: CFTypeRef>(key: CFTypeRef, as typeID: CFTypeID) -> T? {
        guard let value = self[key], CFGetTypeID(value) == typeID else { return nil }

        return value as? T
    }

    public func readString(key: String) -> String? {
        self.readString(key: CFString.fromString(key))
    }

    public func readString(key: CFString) -> String? {
        let string: CFString? = self[key, as: CFStringGetTypeID()]

        return string?.toString()
    }
}

extension CFDictionary: XPCConvertible {
    public static func fromXPCObject(_ xpcObject: xpc_object_t) -> Self? {
        let count = xpc_dictionary_get_count(xpcObject)

        var keyCallBacks = kCFTypeDictionaryKeyCallBacks
        var valueCallBacks = kCFTypeDictionaryValueCallBacks

        let dict = CFDictionaryCreateMutable(kCFAllocatorDefault, count, &keyCallBacks, &valueCallBacks)
        let utf8 = CFStringBuiltInEncodings.UTF8.rawValue

        xpc_dictionary_apply(xpcObject) {
            if let key = CFStringCreateWithCString(kCFAllocatorDefault, $0, utf8),
               let value = convertFromXPC($1) {
                CFDictionarySetValue(
                    dict,
                    unsafeBitCast(key as AnyObject, to: UnsafeRawPointer.self),
                    unsafeBitCast(value as AnyObject, to: UnsafeRawPointer.self)
                )
            }

            return true
        }

        return dict.map { unsafeDowncast($0, to: self) }
    }

    public func toXPCObject() -> xpc_object_t? {
        let count = CFDictionaryGetCount(self)

        let keys = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { keys.deallocate() }

        let objs = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { objs.deallocate() }

        let xpcKeys = UnsafeMutablePointer<UnsafePointer<CChar>>.allocate(capacity: count)
        defer { xpcKeys.deallocate() }

        CFDictionaryGetKeysAndValues(self, keys, objs)

        var xpcCount = 0

        let xpcObjs: [xpc_object_t?] = (0..<count).compactMap {
            if let pointer = objs[$0], let xpcObject = convertToXPC(pointer) {
                unsafeBitCast(keys[$0], to: CFString.self).withCString {
                    xpcKeys[xpcCount] = UnsafePointer(strdup($0))
                }

                xpcCount += 1

                return xpcObject
            } else {
                return nil
            }
        }

        defer { (0..<xpcCount).forEach { free(UnsafeMutableRawPointer(mutating: xpcKeys[$0])) } }

        return xpcObjs.withUnsafeBufferPointer { xpc_dictionary_create(xpcKeys, $0.baseAddress, $0.count) }
    }
}
