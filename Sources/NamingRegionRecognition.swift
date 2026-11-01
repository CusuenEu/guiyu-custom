import AppKit
import PDFKit
import Vision
import ImageIO
import CoreImage

// Regions use normalized, top-left image coordinates, independent of viewport/zoom.
enum NamingRegionGeometry {
    static func point(_ p:CGPoint,turns:Int) -> CGPoint {
        switch (turns % 4 + 4) % 4 {
        case 1: return CGPoint(x:1-p.y,y:p.x)
        case 2: return CGPoint(x:1-p.x,y:1-p.y)
        case 3: return CGPoint(x:p.y,y:1-p.x)
        default: return p
        }
    }
    static func rotated(_ rect:CGRect,turns:Int) -> CGRect {
        let points = [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)].map{point($0,turns:turns)}
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
    }
    static func region(from drag:CGRect,imageRect:CGRect,turns:Int) -> CGRect? {
        let clipped = drag.standardized.intersection(imageRect)
        guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8, imageRect.width > 0, imageRect.height > 0 else { return nil }
        let displayed = CGRect(x:(clipped.minX-imageRect.minX)/imageRect.width,y:(clipped.minY-imageRect.minY)/imageRect.height,width:clipped.width/imageRect.width,height:clipped.height/imageRect.height)
        return rotated(displayed,turns:-turns).intersection(CGRect(x:0,y:0,width:1,height:1))
    }
    static func crop(_ image:CGImage,region:CGRect) -> CGImage? {
        let bounded = region.standardized.intersection(CGRect(x:0,y:0,width:1,height:1))
        guard !bounded.isNull else { return nil }
        let pixels = CGRect(x:bounded.minX*CGFloat(image.width),y:bounded.minY*CGFloat(image.height),width:bounded.width*CGFloat(image.width),height:bounded.height*CGFloat(image.height)).integral.intersection(CGRect(x:0,y:0,width:image.width,height:image.height))
        guard pixels.width >= 8, pixels.height >= 8 else { return nil }
        return image.cropping(to:pixels)
    }
    static func image(_ image:CGImage,turns:Int) -> CGImage? {
        let orientations:[CGImagePropertyOrientation] = [.up,.right,.down,.left]
        let turn = (turns % 4 + 4) % 4
        guard turn != 0 else { return image }
        let rotated = CIImage(cgImage:image).oriented(orientations[turn])
        return CIContext(options:[.cacheIntermediates:false]).createCGImage(rotated,from:rotated.extent)
    }
}

func cleanRegionRecognizedText(_ raw:String) -> String {
    raw.replacingOccurrences(of:"[\\s\\p{Cc}<>:\"/\\\\|?*：？。]+",with:"",options:.regularExpression).trimmingCharacters(in:CharacterSet(charactersIn:"."))
}
func selectedNamingText(_ text:String,range:NSRange) -> String {
    let value = text as NSString
    guard range.location != NSNotFound, range.length > 0, range.location <= value.length, range.length <= value.length-range.location else { return text }
    return value.substring(with:range)
}

struct NamingPreviewPage {
    let number:Int
    let image:CGImage
}
struct NamingPreviewSelection {
    var region:CGRect?
    var turns = 0
    var text = ""
    var recognizing = false
    var message = ""
}
final class NamingCropTask: @unchecked Sendable {
    let cancellation = IndexCancellation()
    private let lock = NSLock()
    private var request:VNRequest?
    func attach(_ value:VNRequest) {
        lock.lock();request = value;let cancelled = cancellation.isCancelled;lock.unlock()
        if cancelled { value.cancel() }
    }
    func cancel() {
        cancellation.cancel();lock.lock();let value = request;lock.unlock();value?.cancel()
    }
}
func recognizeNamingCrop(_ image:CGImage,task:NamingCropTask) throws -> String {
    guard !task.cancellation.isCancelled else { return "" }
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["zh-Hans","en-US"]
    request.recognitionLevel = .accurate;request.usesLanguageCorrection = true
    task.attach(request)
    try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
    guard !task.cancellation.isCancelled else { return "" }
    return (request.results ?? []).sorted {
        abs($0.boundingBox.midY-$1.boundingBox.midY) > 0.015 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
    }.compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
}

func loadNamingPreview(_ target:NamingTarget,token:IndexCancellation) throws -> [NamingPreviewPage] {
    guard !token.isCancelled else { return [] }
    let url = URL(fileURLWithPath:target.path), ext = url.pathExtension.lowercased()
    if ext == "pdf" {
        guard let document = PDFDocument(url:url) else { throw namingError("无法读取此 PDF，可继续手动命名。") }
        guard !document.isLocked else { throw namingError("PDF 已加密，请先解锁文档再重试；仍可手动命名。") }
        guard document.pageCount > 0 else { throw namingError("PDF 没有可预览的页面，可手动命名。") }
        var result:[NamingPreviewPage] = []
        for index in 0..<min(2,document.pageCount) {
            guard !token.isCancelled else { return [] }
            try autoreleasepool {
                guard let page = document.page(at:index) else { throw namingError("此页无法预览，可使用其他候选或手动命名。") }
                let bounds = page.bounds(for:.mediaBox)
                guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite else { throw namingError("文档页面尺寸无效，可手动命名。") }
                let image = page.thumbnail(of:NSSize(width:2200,height:2800),for:.mediaBox)
                guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw namingError("页面预览生成失败，可手动命名。") }
                result.append(NamingPreviewPage(number:index+1,image:cg))
            }
        }
        return result
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2800] as CFDictionary) else { throw namingError("无法预览此图片，可继续手动命名。") }
    return [NamingPreviewPage(number:1,image:image)]
}

@MainActor final class NamingPreviewModel:ObservableObject {
    @Published private(set) var pages:[NamingPreviewPage] = []
    @Published private(set) var selectedPage = 0
    @Published private(set) var displayImage:CGImage?
    @Published private(set) var selections:[Int:NamingPreviewSelection] = [:]
    @Published private(set) var loading = false
    @Published private(set) var notice = ""
    @Published var zoom:CGFloat = 1
    private var loadToken = IndexCancellation()
    private var activeTask:NamingCropTask?
    private var generation = UUID()
    private var closed = false
    private var target:NamingTarget?
    private let recognizer:(CGImage,NamingCropTask) throws -> String
    private let loader:(NamingTarget,IndexCancellation) throws -> [NamingPreviewPage]
    init(loader:@escaping (NamingTarget,IndexCancellation) throws -> [NamingPreviewPage] = loadNamingPreview,recognizer:@escaping (CGImage,NamingCropTask) throws -> String = recognizeNamingCrop) { self.loader = loader;self.recognizer = recognizer }
    var state:NamingPreviewSelection { selections[selectedPage] ?? NamingPreviewSelection() }
    func load(_ target:NamingTarget) {
        self.target = target
        guard !target.folder, ["pdf","png","jpg","jpeg","heic","tiff","tif"].contains(URL(fileURLWithPath:target.path).pathExtension.lowercased()) else {
            notice = "此格式暂不支持页面预览，仍可使用推荐名称或手动命名。";return
        }
        loading = true;notice = "";let token = loadToken;let loader = self.loader
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { try loader(target,token) }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, !token.isCancelled else { return }
                self.loading = false
                switch result {
                case .success(let pages): self.pages = pages;self.displayImage = pages.first?.image
                case .failure(let error): self.notice = error.localizedDescription
                }
            }
        }
    }
    private func stopRecognition() {
        generation = UUID();activeTask?.cancel();activeTask = nil
        var value = state;value.recognizing = false;selections[selectedPage] = value
    }
    func selectPage(_ index:Int) {
        guard pages.indices.contains(index),index != selectedPage else { return }
        stopRecognition();selectedPage = index;updateImage()
    }
    func rotate() {
        guard pages.indices.contains(selectedPage) else { return }
        stopRecognition();var value = state;value.turns = (value.turns+1)%4;selections[selectedPage] = value;updateImage()
    }
    private func updateImage() {
        guard pages.indices.contains(selectedPage) else { return }
        displayImage = NamingRegionGeometry.image(pages[selectedPage].image,turns:state.turns)
    }
    func editText(_ text:String) {
        if state.recognizing { stopRecognition() }
        var value = state;value.text = text;value.message = "";selections[selectedPage] = value
    }
    func invalidSelection() {
        stopRecognition();var value = state;value.message = "选框太小，请拖出更大的文字区域。";selections[selectedPage] = value
    }
    func recognize(_ region:CGRect) {
        guard !closed, pages.indices.contains(selectedPage), let target else { return }
        stopRecognition()
        guard target.identity == fileIdentity(target.path), target.modified == (try? URL(fileURLWithPath:target.path).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) else {
            var value = state;value.message = "文件已变更，请关闭后重新打开智能命名。";selections[selectedPage] = value;return
        }
        let image = pages[selectedPage].image, index = selectedPage, task = NamingCropTask(), ticket = generation, turns = state.turns
        activeTask = task
        var value = state;value.region = region;value.text = "";value.recognizing = true;value.message = "";selections[index] = value
        let recognize = recognizer
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let result = Result { () throws -> String in
                // Crop real pixels before OCR; the recognizer never receives the full page.
                guard !task.cancellation.isCancelled, let crop = NamingRegionGeometry.crop(image,region:region),let oriented = NamingRegionGeometry.image(crop,turns:turns) else { throw namingError("选框太小，请重新框选。") }
                return cleanRegionRecognizedText(try recognize(oriented,task))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.closed, self.generation == ticket, self.selectedPage == index, !task.cancellation.isCancelled else { return }
                var value = self.state;value.recognizing = false
                guard target.identity == fileIdentity(target.path),target.modified == (try? URL(fileURLWithPath:target.path).resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) else {
                    value.message = "文件已变更，请关闭后重新打开智能命名。";self.selections[index] = value;self.activeTask = nil;return
                }
                switch result {
                case .success(let text): value.text = text;value.message = text.isEmpty ? "框内未识别到文字，请重新框选或手动输入。" : ""
                case .failure: value.message = "此区域识别失败，请重新框选或手动输入。"
                }
                self.selections[index] = value;self.activeTask = nil
            }
        }
    }
    func cancel() { closed = true;loadToken.cancel();stopRecognition() }
}
