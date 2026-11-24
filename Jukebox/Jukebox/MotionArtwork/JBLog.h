#pragma once
#import <Foundation/Foundation.h>

// JBLog("fmt %@", obj) - NSString-style format, written to the system log.
#define JBLog(fmt, ...) NSLog(@"[Jukebox motion] %@", [NSString stringWithFormat:@fmt, ##__VA_ARGS__])
