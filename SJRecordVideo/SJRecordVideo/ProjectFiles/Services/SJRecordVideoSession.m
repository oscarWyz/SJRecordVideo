//
//  SJRecordVideoSession.m
//  SJRecordVideo
//
//  Created by BlueDancer on 2017/8/3.
//  Copyright © 2017年 SanJiang. All rights reserved.
//

#import "SJRecordVideoSession.h"

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVCaptureFileOutput.h>

#import "NSTimer+Extension.h"

#import <UIKit/UIKit.h>

@interface SJRecordVideoSession (AVCaptureFileOutputRecordingDelegateMethods)<AVCaptureFileOutputRecordingDelegate>

- (void)compoundRecordsMedia;

@end


@interface SJRecordVideoSession ()

@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureDevice *dbVideoDevice;
@property (nonatomic, strong, readonly) AVCaptureDevice *dbAudioDevice;
@property (nonatomic, strong, readonly) AVCaptureDeviceInput *dbVideoInput;
@property (nonatomic, strong, readonly) AVCaptureDeviceInput *dbAudioInput;
@property (nonatomic, strong, readonly) AVCaptureMovieFileOutput *dbMovieOutput;
@property (nonatomic, strong, readonly) AVCaptureVideoPreviewLayer *dbPreviewLayer;
@property (nonatomic, strong, readonly) NSURL *kamera_movieOutURL;
@property (nonatomic, strong, readonly) NSURL *kamera_movieFolderURL;

@property (nonatomic, assign, readwrite) NSInteger kamera_movieRecordIndex;

@property (nonatomic, strong, readonly) NSTimer *exportProgressTimer;
@property (nonatomic, strong, readwrite) AVAssetExportSession *stoppedExportSession;

@property (nonatomic, strong, readwrite) void(^exportedCallBlock)(AVAsset *asset, UIImage *coverImage);
@property (nonatomic, strong, readwrite) void(^pausedCallBlock)();

@property (nonatomic, assign, readwrite) AVCaptureVideoOrientation orientation;
@property (nonatomic, assign, readwrite) BOOL isStopRecord;

@end

@implementation SJRecordVideoSession

@synthesize session = _session;
@synthesize dbVideoDevice = _dbVideoDevice;
@synthesize dbAudioDevice = _dbAudioDevice;
@synthesize dbVideoInput = _dbVideoInput;
@synthesize dbAudioInput = _dbAudioInput;
@synthesize dbMovieOutput = _dbMovieOutput;
@synthesize dbPreviewLayer = _dbPreviewLayer;
@synthesize kamera_movieOutURL = _kamera_movieOutURL;
@synthesize exportProgressTimer = _exportProgressTimer;
@synthesize kamera_movieFolderURL = _kamera_movieFolderURL;

- (instancetype)init {
    self = [super init];
    if ( !self ) return nil;
    [self.session beginConfiguration];
    if ( [self.session canAddInput:self.dbVideoInput] ) [self.session addInput:self.dbVideoInput];
    if ( [self.session canAddInput:self.dbAudioInput] ) [self.session addInput:self.dbAudioInput];
    if ( [self.session canAddOutput:self.dbMovieOutput] ) {
        [self.session addOutput:self.dbMovieOutput];
        AVCaptureConnection *videoConnection = [self.dbMovieOutput connectionWithMediaType:AVMediaTypeVideo];
        if ( videoConnection.isVideoStabilizationSupported ) {
            videoConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
    }
    [self.session commitConfiguration];
    [self resetKamera_movieFolder];
    
    return self;
}


// MARK: Public

- (CALayer *)previewLayer {
    if ( ![self.session isRunning] ) [self.session startRunning];
    return self.dbPreviewLayer;
}

// MARK: Private

// MARK: ------
/*!
 *  返回对应位置的 camera
 */
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)postion {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices ) {
        if ( device.position == postion ) return device;
    }
    return nil;
}

/*!
 *  返回当前活跃的 camera
 */
- (AVCaptureDevice *)activeCamera {
    return self.dbVideoInput.device;
}

/*!
 *  返回不活跃的 camera
 */
- (AVCaptureDevice *)inactiveCamera {
    AVCaptureDevice *device = nil;
    if ( self.cameraCount > 1 ) {
        if ( [self activeCamera].position == AVCaptureDevicePositionBack )
            device = [self cameraWithPosition:AVCaptureDevicePositionFront];
        else
            device = [self cameraWithPosition:AVCaptureDevicePositionBack];
    }
    return device;
}

/*!
 *  可用 camera 数量
 */
- (NSUInteger)cameraCount {
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

/*!
 *  是否有超过 1个 摄像头可用
 */
- (BOOL)canSwitchCameras {
    return self.cameraCount > 1;
}

/*!
 *  视频输出路径
 */
- (NSURL *)kamera_movieOutURL {
    if ( _kamera_movieOutURL ) return _kamera_movieOutURL;
    _kamera_movieOutURL = [self.kamera_movieFolderURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%03zd_db_kamera_movie.mov", self.kamera_movieRecordIndex]];
    self.kamera_movieRecordIndex += 1;
    return _kamera_movieOutURL;
}

- (void)resetKamera_movieFolder {
    // 重置记录索引
    self.kamera_movieRecordIndex = 0;
    NSString *kamera_movieFolderPathStr = [self.kamera_movieFolderURL.absoluteString substringFromIndex:7];
    [[NSFileManager defaultManager] removeItemAtPath:kamera_movieFolderPathStr error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:kamera_movieFolderPathStr withIntermediateDirectories:YES attributes:nil error:nil];
}

- (NSURL *)kamera_movieFolderURL {
    if ( _kamera_movieFolderURL ) return _kamera_movieFolderURL;
    _kamera_movieFolderURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:@"db_kamera_movies"];
    return _kamera_movieFolderURL;
}

// MARK: ------


// MARK: ------

- (BOOL)cameraHasFlash {
    return [[self activeCamera] hasFlash];
}

- (AVCaptureFlashMode)flashMdoe {
    return [[self activeCamera] flashMode];
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode {
    AVCaptureDevice *device = [self activeCamera];
    
    if ( [device isFlashModeSupported:flashMode] ) {
        NSError *error;
        if ( [device lockForConfiguration:&error] ) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        }
        else {
            if ( ![self.delegate respondsToSelector:@selector(deviceConfigurationFaieldWithError:)] ) return;
            [self.delegate deviceConfigurationFaieldWithError:error];
        }
    }
}

- (BOOL)camerahasTorch {
    return [[self activeCamera] hasTorch];
}

// MARK: ------


// MARK: Lazy

- (AVCaptureSession *)session {
    if ( _session ) return _session;
    _session = [AVCaptureSession new];
    return _session;
}

- (AVCaptureDevice *)dbVideoDevice {
    if ( _dbVideoDevice ) return _dbVideoDevice;
    _dbVideoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    return _dbVideoDevice;
}

- (AVCaptureDevice *)dbAudioDevice {
    if ( _dbAudioDevice ) return _dbAudioDevice;
    _dbAudioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    return _dbAudioDevice;
}

- (AVCaptureDeviceInput *)dbVideoInput {
    if ( _dbVideoInput ) return _dbVideoInput;
    _dbVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:self.dbVideoDevice error:NULL];
    return _dbVideoInput;
}

- (AVCaptureDeviceInput *)dbAudioInput {
    if ( _dbAudioInput ) return _dbAudioInput;
    _dbAudioInput = [AVCaptureDeviceInput deviceInputWithDevice:self.dbAudioDevice error:NULL];
    return _dbAudioInput;
}

- (AVCaptureMovieFileOutput *)dbMovieOutput {
    if ( _dbMovieOutput ) return  _dbMovieOutput;
    _dbMovieOutput = [AVCaptureMovieFileOutput new];
    return _dbMovieOutput;
}

- (AVCaptureVideoPreviewLayer *)dbPreviewLayer {
    if ( _dbPreviewLayer ) return _dbPreviewLayer;
    _dbPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    _dbPreviewLayer.frame = [UIScreen mainScreen].bounds;
    return _dbPreviewLayer;
}

- (NSTimer *)exportProgressTimer {
    if ( _exportProgressTimer ) return _exportProgressTimer;
    __weak typeof(self) _self = self;
    void(^exportProgressBlock)() = ^{
        if ( ![_self.delegate respondsToSelector:@selector(session:exportProgress:)] ) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_self.delegate session:_self exportProgress:_self.stoppedExportSession.progress];
        });
    };
    _exportProgressTimer = [NSTimer sj_scheduledTimerWithTimeInterval:0.1 exeBlock:exportProgressBlock repeats:YES];
    return _exportProgressTimer;
}

@end


#import <AssetsLibrary/AssetsLibrary.h>

// MARK: Export Assets

@implementation SJRecordVideoSession (ExportAssets)

- (void)exportAssets:(AVAsset *)asset completionHandle:(void(^)(AVAsset *sandBoxAsset, UIImage *previewImage))block; {
    NSURL *exportURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"_re_.mp4"];
    if ( [[NSFileManager defaultManager] fileExistsAtPath:[exportURL.absoluteString substringFromIndex:7]] ) {
        [[NSFileManager defaultManager] removeItemAtURL:exportURL error:nil];
    }
    self.stoppedExportSession = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetMediumQuality];
    self.stoppedExportSession.outputURL = exportURL;
    self.stoppedExportSession.outputFileType = AVFileTypeMPEG4;
    
    [self.exportProgressTimer fire];
    __weak typeof(self) _self = self;
    [self.stoppedExportSession exportAsynchronouslyWithCompletionHandler:^{
        NSLog(@"导出完成");
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self thumbnailForVideoAtURL:exportURL atTime:kCMTimeZero generatedImage:^(UIImage *image) {
            [self resetKamera_movieFolder];
            AVAsset *asset = [AVAsset assetWithURL:exportURL];
            asset.assetURL = exportURL;
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( block ) block(asset, image);
            });
            // 删除定时器
            [_exportProgressTimer invalidate];
            _exportProgressTimer = nil;
        }];
    }];
}

/*!
 *  @parma  duration    unit is sec.
 *  @parma  diraction   YES is Portrait, NO is Landscape.
 */
- (void)exportAssets:(AVAsset *)asset maxDuration:(NSInteger)duration direction:(short)direction completionHandle:(void(^)(AVAsset *sandBoxAsset, UIImage *previewImage))block; {
    
    NSInteger sourceDuration = asset.duration.value / asset.duration.timescale;
    if ( sourceDuration < duration ) {
        [self exportAssets:asset completionHandle:block];
        return;
    }
    
    AVMutableComposition *compositionM = [AVMutableComposition composition];
    
    AVMutableCompositionTrack *audioTrackM = [compositionM addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *videoTrackM = [compositionM addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    
    if ( 1 == direction ) videoTrackM.preferredTransform = CGAffineTransformMakeRotation(M_PI_2);
    
    CMTimeRange cutRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(duration, 1));
    
    AVAssetTrack *assetAudioTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    AVAssetTrack *assetVideoTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    
    NSError *error;
    [audioTrackM insertTimeRange:cutRange ofTrack:assetAudioTrack atTime:kCMTimeZero error:&error];
    if ( error ) {
        NSLog(@"裁剪出错 error = %@", error);
        return;
    }
    [videoTrackM insertTimeRange:cutRange ofTrack:assetVideoTrack atTime:kCMTimeZero error:&error];
    if ( error ) {
        NSLog(@"裁剪出错 error = %@", error);
        return;
    }
    
    NSURL *exportURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"_re_.mp4"];
    if ( [[NSFileManager defaultManager] fileExistsAtPath:[exportURL.absoluteString substringFromIndex:7]] ) {
        [[NSFileManager defaultManager] removeItemAtURL:exportURL error:nil];
    }
    
    self.stoppedExportSession = [AVAssetExportSession exportSessionWithAsset:compositionM presetName:AVAssetExportPresetMediumQuality];
    self.stoppedExportSession.outputURL = exportURL;
    self.stoppedExportSession.outputFileType = AVFileTypeMPEG4;
    
    [self.exportProgressTimer fire];
    __weak typeof(self) _self = self;
    [self.stoppedExportSession exportAsynchronouslyWithCompletionHandler:^{
        NSLog(@"导出完成");
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        [self thumbnailForVideoAtURL:exportURL atTime:kCMTimeZero generatedImage:^(UIImage *image) {
            [self resetKamera_movieFolder];
            AVAsset *asset = [AVAsset assetWithURL:exportURL];
            asset.assetURL = exportURL;
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( block ) block(asset, image);
            });
            // 删除定时器
            [_exportProgressTimer invalidate];
            _exportProgressTimer = nil;
        }];
    }];
}

@end


NSNotificationName const ThumbnailNotification = @"ThumbnailNotification";

@implementation SJRecordVideoSession (AVCaptureFileOutputRecordingDelegateMethods)

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    NSLog(@"录制完成");
    
    if ( error ) {
        NSLog(@"录制报错 : %@", error);
        if ( ![self.delegate respondsToSelector:@selector(mediaCaptureFaieldWithError:)] ) return;
        [self.delegate mediaCaptureFaieldWithError:error];
    }
    else {
        if ( !self.isStopRecord ) {
            if ( _pausedCallBlock ) _pausedCallBlock();
            _pausedCallBlock = nil;
        }
        
        // 合成操作
        if ( self.isStopRecord )  {
            [self compoundRecordsMedia];
        }
    }
    /*!
     *  清空操作
     */
    _kamera_movieOutURL = nil;
}

- (void)compoundRecordsMedia {
    NSString *kamera_movieFolderPathStr = [_kamera_movieFolderURL.absoluteString substringFromIndex:7];
    NSArray<NSString *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kamera_movieFolderPathStr error:nil];
    
    // 文件排序
    NSStringCompareOptions comparisonOptions = NSNumericSearch;
    NSArray<NSString *> *resultArr = [items sortedArrayUsingComparator:^NSComparisonResult(NSString * _Nonnull obj1, NSString * _Nonnull obj2) {
        NSRange range = NSMakeRange(0, obj1.length);
        return [obj1 compare:obj2 options:comparisonOptions range:range];
    }];
    
    // 合成操作
    AVMutableComposition *compositionM = [AVMutableComposition composition];
    //            compositionM.naturalSize = CGSizeMake(540, 960);
    
    // video track
    AVMutableCompositionTrack *videoTrackM = [compositionM addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    
    // audio track
    AVMutableCompositionTrack *audioTrackM = [compositionM addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    // 考虑:
    // 1. 屏幕方向
    // 2. 摄像头方向
    CGAffineTransform preferredTransform = CGAffineTransformIdentity;
    AVCaptureDevicePosition cameraPosition = [self activeCamera].position;
    switch (_orientation ) {
        case AVCaptureVideoOrientationPortrait: {
            preferredTransform = CGAffineTransformMakeRotation(M_PI_2);
        }
            break;
        case AVCaptureVideoOrientationLandscapeLeft: {
            if ( cameraPosition == AVCaptureDevicePositionBack )
                preferredTransform = CGAffineTransformIdentity;
            else
                preferredTransform = CGAffineTransformMakeRotation(M_PI);
        }
            break;
        case AVCaptureVideoOrientationLandscapeRight: {
            if ( cameraPosition == AVCaptureDevicePositionBack )
                preferredTransform = CGAffineTransformMakeRotation(-M_PI);
            else
                preferredTransform = CGAffineTransformIdentity;
        }
            break;
        default:
            break;
    }
    
    videoTrackM.preferredTransform = preferredTransform;
    
    __block CMTime cursorTime = kCMTimeZero;
    
    for ( int i = 0 ; i < resultArr.count ; i ++ ) {
        NSURL *fileURL = [_kamera_movieFolderURL URLByAppendingPathComponent:resultArr[i]];
        AVAsset *asset = [AVAsset assetWithURL:fileURL];
        
        // asset track
        AVAssetTrack *videoTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        AVAssetTrack *audioTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        
        // insert
        CMTimeRange range = CMTimeRangeMake(kCMTimeZero, asset.duration);
        NSError *error;
        [videoTrackM insertTimeRange:range ofTrack:videoTrack atTime:cursorTime error:&error];
        if ( error ) NSLog(@"A: error: %@", error);
        [audioTrackM insertTimeRange:range ofTrack:audioTrack atTime:cursorTime error:&error];
        if ( error ) NSLog(@"B: error: %@", error);
        
        cursorTime = compositionM.duration;
    }
    
    // 导出
    [self exportAssets:compositionM completionHandle:^(AVAsset *sandBoxAsset, UIImage *previewImage) {
        if ( _exportedCallBlock ) {
            _exportedCallBlock(sandBoxAsset, previewImage);
            _exportedCallBlock = nil;
        }
    }];
}

@end



// MARK: 录制

@implementation SJRecordVideoSession (Record)

/*!
 *  开始录制视频
 */
- (void)startRecordingWithOrientation:(AVCaptureVideoOrientation)orientation {
    
    self.orientation = orientation;
    
    AVCaptureConnection *videoConnection = [self.dbMovieOutput connectionWithMediaType:AVMediaTypeVideo];
    
    if ( [videoConnection isVideoOrientationSupported] ) {
        videoConnection.videoOrientation = orientation;
    }
    
    AVCaptureDevice *device = [self activeCamera];
    if ( device.isSmoothAutoFocusSupported ) {
        NSError *error;
        if ( [device lockForConfiguration:&error] ) {
            device.smoothAutoFocusEnabled = YES;
            [device unlockForConfiguration];
        }
        else {
            if ( ![self.delegate respondsToSelector:@selector(deviceConfigurationFaieldWithError:)] ) return;
            [self.delegate deviceConfigurationFaieldWithError:error];
            NSLog(@"start Error: %@", error);
        }
    }
    [self.dbMovieOutput startRecordingToOutputFileURL:self.kamera_movieOutURL recordingDelegate:self];
}

/*!
 *  是否在录制
 */
- (BOOL)isRecording {
    return _dbMovieOutput.isRecording;
}

/*!
 *  完成录制视频
 */
- (void)stopRecordingAndComplate:(void(^)(AVAsset *asset, UIImage *coverImage))block {
    self.isStopRecord = YES;
    _exportedCallBlock = block;
    
    if ( [self isRecording] ) [self.dbMovieOutput stopRecording];
    else [self compoundRecordsMedia];
}

/*!
 *  暂停录制
 */
- (void)pauseRecordingAndComplete:(void (^)())block {
    if ( ![self isRecording] ) {
        if ( block ) block();
        return;
    }
    self.isStopRecord = NO;
    [self.dbMovieOutput stopRecording];
    _pausedCallBlock = block;
}

/*!
 *  恢复录制
 */
- (void)resumeRecording {
    [self startRecordingWithOrientation:self.orientation];
}

/*!
 *  重置录制
 */
- (void)resetRecordingAndCallBlock:(void(^)())block {
    [self pauseRecordingAndComplete:^{
        [self resetKamera_movieFolder];
        if ( block ) block();
    }];
}

/*!
 *  生成封面
 *  time is second
 */
- (void)thumbnailForVideoAtURL:(NSURL *)videoURL atTime:(CMTime)time generatedImage:(void(^)(UIImage *image))block {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        AVAsset *asset = [AVAsset assetWithURL:videoURL];
        AVAssetImageGenerator *imageGenerator =
        [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        imageGenerator.maximumSize = CGSizeMake(375, 0.0);
        imageGenerator.appliesPreferredTrackTransform = YES;
        CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:nil];
        UIImage *image = [UIImage imageWithCGImage:imageRef];
        CGImageRelease(imageRef);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ( block ) block(image);
        });
    });
}

/*!
 *  批量生成封面
 */
+ (void)batchGeneratedImageAtURL:(NSURL *)videoURL interval:(short)interval completion:(void(^)(NSArray<UIImage *> *imageArr))block {
    [self batchGeneratedImageWithAsset:[AVAsset assetWithURL:videoURL] interval:interval completion:block];
}

/*!
 *  批量生成封面
 *  interval : 几秒钟截一次图
 */
+ (void)batchGeneratedImageWithAsset:(AVAsset *)asset interval:(short)interval completion:(void(^)(NSArray<UIImage *> *imageArr))block {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSMutableArray *arrM = [NSMutableArray new];
        AVAssetImageGenerator *imageGenerator =
        [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        imageGenerator.maximumSize = CGSizeMake(track.naturalSize.width, 0.0);
        imageGenerator.appliesPreferredTrackTransform = YES;
        CMTime duration = asset.duration;
        NSInteger second = duration.value / duration.timescale;
        NSInteger count = second / interval;
        if ( 0 == count ) return;
        __block short time = 0;
        for ( int i = 0 ; i < count ; i ++ ) {
            CGImageRef imageRef = [imageGenerator copyCGImageAtTime:CMTimeMake(time, 1) actualTime:NULL error:nil];
            UIImage *image = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
            [arrM addObject:image];
            time += interval;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ( block ) block(arrM.copy);
        });
    });
}
@end




// MARK: 摄像头

@implementation SJRecordVideoSession (Camera)

/*!
 *  切换摄像头
 */
- (BOOL)switchCameras {
    if ( ![self canSwitchCameras] ) return NO;
    [self resetKamera_movieFolder];
    NSError *error;
    AVCaptureDevice *inactiveVideoDevice = [self inactiveCamera];
    AVCaptureDeviceInput *inactiveVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:inactiveVideoDevice error:&error];
    
    if ( inactiveVideoInput ) {
        [self.session beginConfiguration];
        
        [self.session removeInput:_dbVideoInput];
        
        if ( [self.session canAddInput:inactiveVideoInput] ) {
            [self.session addInput:inactiveVideoInput];
            _dbVideoInput = inactiveVideoInput;
        }
        else {
            [self.session addInput:_dbVideoInput];
        }
        
        [self.session commitConfiguration];
    }
    else {
        if ( [self.delegate respondsToSelector:@selector(deviceConfigurationFaieldWithError:)] ) [self.delegate deviceConfigurationFaieldWithError:error];
        return NO;
    }
    return YES;
}

- (void)setCameraPosition:(AVCaptureDevicePosition)cameraPosition {
    if ( [self activeCamera].position == cameraPosition ) return;
    [self switchCameras];
}

- (AVCaptureDevicePosition)cameraPosition {
    return [self activeCamera].position;
}

@end





// MARK: 闪光灯

@implementation SJRecordVideoSession (Torch)

- (AVCaptureTorchMode)torchMode {
    return [[self activeCamera] torchMode];
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    AVCaptureDevice *device = [self activeCamera];
    if ( [device isTorchModeSupported:torchMode] ) {
        NSError *error;
        if ( [device lockForConfiguration:&error] ) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        }
        else {
            if ( ![self.delegate respondsToSelector:@selector(deviceConfigurationFaieldWithError:)] ) return;
            [self.delegate deviceConfigurationFaieldWithError:error];
        }
    }
}

@end