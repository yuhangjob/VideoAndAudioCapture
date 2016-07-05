//
//  ViewController.m
//  AVCaptureSession
//
//  Created by 刘宇航 on 16/7/1.
//  Copyright © 2016年 刘宇航. All rights reserved.
//
#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "AACEncoder.h"
#import "H264Encoder.h"
#import "avformat.h"
#define CAPTURE_FRAMES_PER_SECOND       20
#define SAMPLE_RATE                     44100
#define VideoWidth                      480
#define VideoHeight                     640
@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate,H264EncoderDelegate>
// 负责输如何输出设备之间的数据传递
@property (nonatomic, strong) AVCaptureSession           *session;
// 队列
@property (nonatomic, strong) dispatch_queue_t           videoQueue;
@property (nonatomic, strong) dispatch_queue_t           AudioQueue;

// 负责从 AVCaptureDevice 获得输入数据
@property (nonatomic, strong) AVCaptureDeviceInput       *captureDeviceInput;
@property (nonatomic, strong) AVCaptureVideoDataOutput   *videoOutput;
@property (nonatomic, strong) AVCaptureConnection        *videoConnection;
@property (nonatomic, strong) AVCaptureConnection        *audioConnection;
// 拍摄预览图层
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) H264Encoder                *h264Encoder;
@property (nonatomic, strong) AACEncoder                 *aacEncoder;
@property (nonatomic, strong) NSMutableData              *data;
@property (nonatomic, copy  ) NSString                   *h264File;
@property (nonatomic, strong) NSFileHandle               *fileHandle;
@property (nonatomic, strong) UIButton                   *startBtn;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _data = [NSMutableData new];
    //初始化AVCaptureSession
    _session = [AVCaptureSession new];
    
//    [self setupAudioCapture];
//    [self setupVideoCapture];
    [self initStartBtn];
}
#pragma mark - 设置音频
- (void)setupAudioCapture {
    
    self.aacEncoder = [AACEncoder new];
    
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    
    NSError *error = nil;
    
    AVCaptureDeviceInput *audioInput = [[AVCaptureDeviceInput alloc]initWithDevice:audioDevice error:&error];
    
    if (error) {
        
        NSLog(@"Error getting audio input device:%@",error.description);
    }
    
    if ([self.session canAddInput:audioInput]) {
        
        [self.session addInput:audioInput];
    }
    
    self.AudioQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
    
    AVCaptureAudioDataOutput *audioOutput = [AVCaptureAudioDataOutput new];
    [audioOutput setSampleBufferDelegate:self queue:self.AudioQueue];
    
    if ([self.session canAddOutput:audioOutput]) {
        
        [self.session addOutput:audioOutput];
    }
    
    self.audioConnection = [audioOutput connectionWithMediaType:AVMediaTypeAudio];
    

}
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices )
        if ( device.position == position )
            return device;
    return nil;
}

#pragma mark - 设置视频 capture
- (void)setupVideoCapture {
    
   
    self.h264Encoder = [H264Encoder new];
    [self.h264Encoder initWithConfiguration];
    [self.h264Encoder initEncode:480 height:640];
    self.h264Encoder.delegate = self;

    if ([_session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        // 设置分辨率
        _session.sessionPreset = AVCaptureSessionPreset1280x720;
    }
//
    //设置采集的 Video 和 Audio 格式，这两个是分开设置的，也就是说，你可以只采集视频。
    //配置采集输入源(摄像头)
    
    NSError *error = nil;
    //获得一个采集设备, 例如前置/后置摄像头
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
//    videoDevice = [self cameraWithPosition:AVCaptureDevicePositionBack];
 //   videoDevice.position = AVCaptureDevicePositionBack;
    //用设备初始化一个采集的输入对象
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error) {
        NSLog(@"Error getting video input device:%@",error.description);
        
    }
    if ([_session canAddInput:videoInput]) {
        [_session addInput:videoInput];
    }
    
    //配置采集输出,即我们取得视频图像的接口
    _videoQueue = dispatch_queue_create("Video Capture Queue", DISPATCH_QUEUE_SERIAL);
    _videoOutput = [AVCaptureVideoDataOutput new];
    [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
    
    // 配置输出视频图像格式
    NSDictionary *captureSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    _videoOutput.videoSettings = captureSettings;
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    
    if ([_session canAddOutput:_videoOutput]) {
        [_session addOutput:_videoOutput];
    }
    // 保存Connection,用于SampleBufferDelegate中判断数据来源(video or audio?)
    _videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    
    // 启动session
    [_session startRunning];
    //将当前硬件采集视频图像显示到屏幕
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill; // 设置预览时的视频缩放方式
    [[_previewLayer connection] setVideoOrientation:AVCaptureVideoOrientationPortrait]; // 设置视频的朝向
    
    _previewLayer.frame = CGRectMake(0, 20, self.view.frame.size.height, self.view.frame.size.height - 80);
    [self.view.layer addSublayer:_previewLayer];
    
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    
    self.h264File = [documentsDirectory stringByAppendingString:@"lyh.h264"];
    [fileManager removeItemAtPath:self.h264File error:nil];
    [fileManager createFileAtPath:self.h264File contents:nil attributes:nil];
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.h264File];
    
   

}

#pragma mark - 实现 AVCaptureOutputDelegate：
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CMTime pts = CMSampleBufferGetDuration(sampleBuffer);
    
    double dPTS = (double)(pts.value) / pts.timescale;
    NSLog(@"DPTS is %f",dPTS);
    
    // 这里的sampleBuffer就是采集到的数据了，但它是Video还是Audio的数据，得根据connection来判断
    if (connection == _videoConnection) {  // Video
        //NSLog(@"在这里获得video sampleBuffer，做进一步处理（编码H.264）");
   
         // 取得当前视频尺寸信息
         CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
         NSInteger width = CVPixelBufferGetWidth(pixelBuffer);
         NSInteger height = CVPixelBufferGetHeight(pixelBuffer);
        [self.h264Encoder encode:sampleBuffer];
    
    } else if (connection == _audioConnection) {  // Audio
        
        //NSLog(@"这里获得audio sampleBuffer，做进一步处理（编码AAC）");
        
        [self.aacEncoder encodeSampleBuffer:sampleBuffer completionBlock:^(NSData *encodedData, NSError *error) {
            
            if (encodedData) {
                
                NSLog(@"Audio data (%lu):%@", (unsigned long)encodedData.length,encodedData.description);
#pragma mark -  音频数据(encodedData)
                [self.data appendData:encodedData];
            }else {
                
                NSLog(@"Error encoding AAC: %@", error);

            }

        }];
        
    }
    
}

- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps {
    
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    [_fileHandle writeData:ByteHeader];
    [_fileHandle writeData:sps];
    [_fileHandle writeData:ByteHeader];
    [_fileHandle writeData:pps];
    
//    avformat_alloc_output_context2(<#AVFormatContext **ctx#>, <#AVOutputFormat *oformat#>, <#const char *format_name#>, <#const char *filename#>)
    
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame {
    
    NSLog(@"Video data (%lu):%@", (unsigned long)data.length,data.description);
    
    if (_fileHandle != NULL)
    {
        const char bytes[] = "\x00\x00\x00\x01";
        size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
        NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
        
#pragma mark
#pragma mark - 视频数据(data)
        
        [_fileHandle writeData:ByteHeader];
        //[fileHandle writeData:UnitHeader];
        [_fileHandle writeData:data];
        
    }
    
}

#pragma mark - 录制
- (void)startBtnClicked:(UIButton *)btn
{
    btn.selected = !btn.selected;
    
    if (btn.selected)
    {
        [self startCamera];
        [_startBtn setTitle:@"Stop" forState:UIControlStateNormal];
        
    }
    else
    {
        [_startBtn setTitle:@"Start" forState:UIControlStateNormal];
        [self stopCarmera];
    }
    
}

- (void) startCamera
{
    [self setupAudioCapture];
    [self setupVideoCapture];
    [self.session commitConfiguration];
    [self.session startRunning];
}

- (void) stopCarmera
{
//    [_h264Encoder End];
    [_session stopRunning];
//    //close(fd);
    [_fileHandle closeFile];
    _fileHandle = NULL;
//
    // 获取程序Documents目录路径
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSMutableString * path = [[NSMutableString alloc]initWithString:documentsDirectory];
    [path appendString:@"/AACFile"];
    
    [_data writeToFile:path atomically:YES];
    
}

- (void)initStartBtn
{
    _startBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _startBtn.frame = CGRectMake(0, 0, 100, 40);
    _startBtn.backgroundColor = [UIColor lightGrayColor];
    _startBtn.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2, [UIScreen mainScreen].bounds.size.height - 30);
    [_startBtn addTarget:self action:@selector(startBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
    [_startBtn setTitle:@"Start" forState:UIControlStateNormal];
    [_startBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.view addSubview:_startBtn];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



@end
