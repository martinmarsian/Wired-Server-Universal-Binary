//
//  WPDatabaseManager.m
//  Wired Server
//
//  Created by Rafaël Warnault on 08/01/12.
//  Copyright (c) 2012 Read-Write. All rights reserved.
//

#import "WPDatabaseManager.h"

static sqlite3                      *_db;
static WPDatabaseResultsBlock       _currentBlock;


static int callback(void *NotUsed, int argc, char **argv, char **azColName){
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    int i;
    
    for(i=0; i<argc; i++){
        [result setValue:[NSString stringWithCString:(argv[i] ? argv[i] : "NULL") encoding:NSUTF8StringEncoding]
                  forKey:[NSString stringWithCString:azColName[i] encoding:NSUTF8StringEncoding]];
    }
    
    _currentBlock(result);
    
    [_currentBlock release];
    _currentBlock = nil;
    
    return 0;
}



@implementation WPDatabaseManager

+ (id)databaseManagerWithPath:(NSString *)string {
    return [[[[self class] alloc] initWithDatabasePath:string] autorelease];
}

- (id)initWithDatabasePath:(NSString *)string {
    self = [super init];
    if (self) {
        _dbPath = [string retain];
        _isOpen = NO;
    }
    return self;
}

- (void)dealloc {
    
    _db = NULL;
    
    [_dbPath release];
    [super dealloc];
}

- (BOOL)open {
    if(!_dbPath)
        return NO;
        
    if(sqlite3_open([_dbPath UTF8String], &_db)){
        fprintf(stderr, "ERROR: Can't open database: %s\n", sqlite3_errmsg(_db));
        sqlite3_close(_db);
        return NO;
    }
    
    _isOpen = YES;
    return YES;
}

- (void)close {
    if(_db != NULL)
        sqlite3_close(_db);
    
    if(_currentBlock) {
        [_currentBlock release];
        _currentBlock = nil;
    }
}

- (BOOL)executeQuery:(NSString *)string withBlock:(WPDatabaseResultsBlock)block {
    
    char *zErrMsg = 0;
    
    if(_currentBlock == nil) {
        _currentBlock = [block copy];
        
        if(sqlite3_exec(_db, [string UTF8String], callback, 0, &zErrMsg) != SQLITE_OK) {
            fprintf(stderr, "ERROR (SQL): %s\n", zErrMsg);
            sqlite3_free(zErrMsg);
            return NO;
        }
        return YES;
        
    } else {
        NSLog(@"ERROR: Previous query appears to be not closed.");
        return NO;
    }
    
    return YES;
}

- (BOOL)executeQuery:(NSString *)sql withParameters:(NSArray *)parameters block:(WPDatabaseResultsBlock)block {
    sqlite3_stmt    *stmt = NULL;
    int             rc;

    if(sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
        fprintf(stderr, "ERROR (SQL prepare): %s\n", sqlite3_errmsg(_db));
        return NO;
    }

    for(NSUInteger i = 0; i < [parameters count]; i++) {
        sqlite3_bind_text(stmt, (int)(i + 1),
                          [[parameters objectAtIndex:i] UTF8String], -1, SQLITE_TRANSIENT);
    }

    while((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if(block) {
            NSMutableDictionary *result = [NSMutableDictionary dictionary];
            for(int col = 0; col < sqlite3_column_count(stmt); col++) {
                const char *colName = sqlite3_column_name(stmt, col);
                const unsigned char *colVal  = sqlite3_column_text(stmt, col);
                [result setValue:(colVal ? [NSString stringWithUTF8String:(const char *)colVal] : @"NULL")
                          forKey:[NSString stringWithUTF8String:colName]];
            }
            block(result);
        }
    }

    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE);
}

- (BOOL)isOpen {
    return _isOpen;
}


@end
