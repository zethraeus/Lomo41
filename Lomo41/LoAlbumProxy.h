//
//  LoAlbumProxy.h
//  Lomo41
//
//  Created by Adam Zethraeus on 1/11/14.
//  Copyright (c) 2014 Very Nice Co. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LoAlbumProxy : NSObject

@property (nonatomic, strong) NSMutableArray *assets;

- (id)initForAlbum: (NSString *)albumName;
- (void)addImage: (UIImage *)image;
- (void)deleteAssetAtIndex:(NSUInteger)index withCompletionBlock:(void(^)())block;
- (void)updateAssets;
- (void)updateAssetsWithCompletionBlock:(void(^)())block;
- (void)deleteAssetList:(NSMutableArray *)list withCompletionBlock:(void(^)())block;

@end
