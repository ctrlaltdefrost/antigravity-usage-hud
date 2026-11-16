import AppKit
import Metal
import MetalKit
import SwiftUI
import simd

/// GPU-accelerated Iron Man / cyberpunk holographic reactor backdrop using runtime-compiled Metal shaders,
/// with an automatic SwiftUI `Canvas` fallback when Metal is unavailable.
public struct MetalReactorBackdrop: NSViewRepresentable {
    public let theme: HUDTheme
    public let activityIntensity: Double
    public let isPulseActive: Bool
    public let cornerRadius: CGFloat

    public init(
        theme: HUDTheme,
        activityIntensity: Double = 0.25,
        isPulseActive: Bool = false,
        cornerRadius: CGFloat = 18
    ) {
        self.theme = theme
        self.activityIntensity = min(max(activityIntensity, 0.0), 1.0)
        self.isPulseActive = isPulseActive
        self.cornerRadius = cornerRadius
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            theme: theme,
            activityIntensity: activityIntensity,
            isPulseActive: isPulseActive
        )
    }

    public func makeNSView(context: Context) -> NSView {
        let container = ReactorContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        if let mtkView = context.coordinator.makeMetalViewIfSupported(frame: container.bounds) {
            mtkView.autoresizingMask = [.width, .height]
            container.addSubview(mtkView)
            context.coordinator.mode = .metal(mtkView)
        } else {
            let fallbackView = NSHostingView(
                rootView: FallbackReactorCanvasView(
                    theme: theme,
                    activityIntensity: activityIntensity,
                    isPulseActive: isPulseActive
                )
            )
            fallbackView.frame = container.bounds
            fallbackView.autoresizingMask = [.width, .height]
            fallbackView.wantsLayer = true
            fallbackView.layer?.backgroundColor = NSColor.clear.cgColor
            container.addSubview(fallbackView)
            context.coordinator.mode = .fallback(fallbackView)
        }

        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous

        let clampedIntensity = min(max(activityIntensity, 0.0), 1.0)
        context.coordinator.updateState(
            theme: theme,
            activityIntensity: clampedIntensity,
            isPulseActive: isPulseActive
        )
    }
}

// MARK: - Uniform Layout (96 bytes, 16-byte aligned for Metal)

private struct ReactorUniforms {
    var time: Float
    var intensity: Float
    var pulse: Float
    var aspect: Float
    var resolution: SIMD2<Float>
    var padding: SIMD2<Float>
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
    var glassTint: SIMD4<Float>
}

// MARK: - Container View

private final class ReactorContainerView: NSView {
    override var isOpaque: Bool { false }
}

private final class ReactorMTKView: MTKView {
    private var occlusionObserver: NSObjectProtocol?

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        guard let window else {
            isPaused = true
            return
        }
        isPaused = !window.isVisible
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let currentWindow = self.window else { return }
                self.isPaused = !(currentWindow.isVisible && currentWindow.occlusionState.contains(.visible))
            }
        }
    }
}

// MARK: - Coordinator & Metal Renderer

public extension MetalReactorBackdrop {
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        fileprivate enum RenderMode {
            case none
            case metal(MTKView)
            case fallback(NSHostingView<FallbackReactorCanvasView>)
        }

        fileprivate var mode: RenderMode = .none

        private var theme: HUDTheme
        private var targetIntensity: Float
        private var targetPulse: Float
        private var smoothedIntensity: Float
        private var smoothedPulse: Float
        private var lastTimestamp: CFTimeInterval
        private var elapsedPhase: Float = 0

        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pipelineState: MTLRenderPipelineState?

        init(theme: HUDTheme, activityIntensity: Double, isPulseActive: Bool) {
            self.theme = theme
            let initialIntensity = Float(min(max(activityIntensity, 0.0), 1.0))
            let initialPulse: Float = isPulseActive ? 1.0 : 0.0
            self.targetIntensity = initialIntensity
            self.targetPulse = initialPulse
            self.smoothedIntensity = initialIntensity
            self.smoothedPulse = initialPulse
            self.lastTimestamp = CACurrentMediaTime()
            super.init()
        }

        func makeMetalViewIfSupported(frame: CGRect) -> MTKView? {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue() else {
                return nil
            }

            do {
                let library = try device.makeLibrary(source: Self.embeddedMetalSource, options: nil)
                guard let vertexFn = library.makeFunction(name: "reactorVertex"),
                      let fragmentFn = library.makeFunction(name: "reactorFragment") else {
                    return nil
                }

                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertexFn
                descriptor.fragmentFunction = fragmentFn
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                descriptor.colorAttachments[0].isBlendingEnabled = false

                let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                self.device = device
                self.commandQueue = queue
                self.pipelineState = pipeline

                let view = ReactorMTKView(frame: frame, device: device)
                view.delegate = self
                view.colorPixelFormat = .bgra8Unorm
                view.framebufferOnly = true
                view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                view.wantsLayer = true
                view.layer?.isOpaque = false
                view.layer?.backgroundColor = NSColor.clear.cgColor
                view.preferredFramesPerSecond = preferredFPS()
                view.isPaused = true
                view.enableSetNeedsDisplay = false
                return view
            } catch {
                return nil
            }
        }

        func updateState(theme: HUDTheme, activityIntensity: Double, isPulseActive: Bool) {
            self.theme = theme
            self.targetIntensity = Float(activityIntensity)
            self.targetPulse = isPulseActive ? 1.0 : 0.0

            switch mode {
            case .metal(let mtkView):
                mtkView.preferredFramesPerSecond = preferredFPS()
            case .fallback(let hostingView):
                hostingView.rootView = FallbackReactorCanvasView(
                    theme: theme,
                    activityIntensity: activityIntensity,
                    isPulseActive: isPulseActive
                )
            case .none:
                break
            }
        }

        private func preferredFPS() -> Int {
            (targetPulse > 0.5 || targetIntensity > 0.25) ? 15 : 8
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Resolution uniform updates automatically every frame from drawableSize.
        }

        public func draw(in view: MTKView) {
            guard let pipelineState,
                  let commandQueue,
                  view.drawableSize.width > 0,
                  view.drawableSize.height > 0,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            let now = CACurrentMediaTime()
            let dt = Float(min(max(now - lastTimestamp, 0.0), 0.1))
            lastTimestamp = now

            // Smooth acceleration/deceleration so energy surges feel organic and physical.
            let smoothing = min(dt * 4.5, 1.0)
            smoothedIntensity += (targetIntensity - smoothedIntensity) * smoothing
            smoothedPulse += (targetPulse - smoothedPulse) * smoothing
            elapsedPhase += dt * (1.0 + smoothedIntensity * 1.15 + smoothedPulse * 0.75)

            let width = Float(view.drawableSize.width)
            let height = Float(view.drawableSize.height)
            var uniforms = ReactorUniforms(
                time: elapsedPhase,
                intensity: smoothedIntensity,
                pulse: smoothedPulse,
                aspect: width / max(height, 1.0),
                resolution: SIMD2<Float>(width, height),
                padding: .zero,
                primary: theme.primarySIMD,
                secondary: theme.secondarySIMD,
                accent: theme.accentSIMD,
                glassTint: theme.glassTintSIMD
            )

            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ReactorUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        private static let embeddedMetalSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct ReactorUniforms {
            float time;
            float intensity;
            float pulse;
            float aspect;
            float2 resolution;
            float2 padding;
            float4 primary;
            float4 secondary;
            float4 accent;
            float4 glassTint;
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut reactorVertex(uint vertexID [[vertex_id]]) {
            float2 positions[3] = {
                float2(-1.0, -1.0),
                float2( 3.0, -1.0),
                float2(-1.0,  3.0)
            };
            VertexOut out;
            float2 pos = positions[vertexID];
            out.position = float4(pos, 0.0, 1.0);
            out.uv = float2(pos.x * 0.5 + 0.5, 1.0 - (pos.y * 0.5 + 0.5));
            return out;
        }

        // Exact hexagonal lattice edge distance for holographic interference pattern.
        float hexEdgeDist(float2 p) {
            p = abs(p);
            float c = dot(p, normalize(float2(1.0, 1.7320508)));
            return max(c, p.x);
        }

        float hexGridMask(float2 coord) {
            float2 r = float2(1.0, 1.7320508);
            float2 h = r * 0.5;
            float2 a = fract(coord / r) * r - h;
            float2 b = fract((coord - h) / r) * r - h;
            float2 gv = dot(a, a) < dot(b, b) ? a : b;
            float edge = 0.5 - hexEdgeDist(gv);
            return 1.0 - smoothstep(0.0, 0.065, edge);
        }

        fragment float4 reactorFragment(VertexOut in [[stage_in]],
                                        constant ReactorUniforms& u [[buffer(0)]]) {
            float2 uv = clamp(in.uv, 0.0, 1.0);
            float2 center = float2(0.5, 0.44);
            float2 p = uv - center;
            p.x *= u.aspect;

            float dist = length(p);
            float angle = atan2(p.y, p.x);

            // 1. Deep translucent dark obsidian glass base for razor-sharp foreground text legibility.
            float3 baseDark = mix(u.glassTint.rgb * 0.65, float3(0.015, 0.022, 0.038), 0.55);
            float diagonalShade = mix(0.92, 1.12, clamp(1.0 - uv.y * 0.7 - uv.x * 0.25, 0.0, 1.0));
            float3 col = baseDark * diagonalShade;

            // 2. Calm, steady radial reactor core atmospheric glow.
            float coreFalloff = exp(-dist * dist * 4.2);
            float rotA = sin(angle * 3.0 - u.time * 0.45) * 0.5 + 0.5;
            float rotB = sin(angle * 6.0 + u.time * 0.65) * 0.5 + 0.5;
            float turbine = mix(rotA, rotB, 0.45);

            float energyBoost = 0.52 + u.intensity * 0.42 + u.pulse * 0.25;
            col += u.secondary.rgb * coreFalloff * (0.13 + 0.05 * turbine) * energyBoost;
            col += u.primary.rgb * exp(-dist * dist * 10.5) * (0.10 + 0.04 * rotA) * energyBoost;

            // 3. Drifting holographic micro-grid + hex interference shimmer (in screen-space units).
            float scaleBase = min(u.resolution.x, u.resolution.y);
            float pixelScale = max(scaleBase / 16.0, 24.0);
            float2 gridCoord = (uv * u.resolution) / pixelScale;
            gridCoord += float2(u.time * 0.09, -u.time * 0.06);

            float2 gridFract = abs(fract(gridCoord - 0.5) - 0.5) / max(fwidth(gridCoord), float2(0.001));
            float gridLine = 1.0 - min(min(gridFract.x, gridFract.y), 1.0);
            float gridMask = smoothstep(1.15, 0.08, dist);
            col += u.primary.rgb * gridLine * 0.055 * gridMask * (0.7 + 0.5 * u.intensity);

            // Hex lattice shimmer modulated by gentle interference wave
            float2 hexCoord = (uv * u.resolution) / (pixelScale * 1.45) + float2(-u.time * 0.04, u.time * 0.03);
            float hexLines = hexGridMask(hexCoord);
            float shimmerWave = 0.5 + 0.5 * sin(uv.x * 3.5 + uv.y * 2.5 - u.time * 0.9);
            float hexOpacity = (0.035 + 0.040 * u.intensity + 0.025 * u.pulse) * (0.4 + 0.6 * shimmerWave);
            col += mix(u.secondary.rgb, u.accent.rgb, shimmerWave) * hexLines * hexOpacity * gridMask;

            // 4. Gentle horizontal radar scanline sweep + ultra-faint CRT micro-texture.
            float sweepPos = fract(u.time * (0.14 + u.intensity * 0.10));
            float sweepDist = uv.y - sweepPos;
            // Wrap distance cleanly across [0, 1]
            if (sweepDist > 0.5) sweepDist -= 1.0;
            if (sweepDist < -0.5) sweepDist += 1.0;

            float sweepBeam = exp(-abs(sweepDist) * 58.0);
            float sweepWake = smoothstep(-0.14, 0.0, sweepDist) * step(sweepDist, 0.0) * 0.45;
            col += mix(u.primary.rgb, u.accent.rgb, 0.5) * (sweepBeam * 0.085 + sweepWake * 0.040) * (0.75 + 0.35 * u.pulse);

            // Ultra-fine scanlines (subtle 1.5% texture)
            float microScan = 0.5 + 0.5 * sin(uv.y * u.resolution.y * 0.85);
            col *= (0.985 + 0.015 * microScan);

            // 5. Edge vignette & crisp luminous inner perimeter glow.
            float2 edgeDist = min(uv, 1.0 - uv);
            float minEdge = min(edgeDist.x * u.aspect, edgeDist.y);
            float rimGlow = exp(-minEdge * 42.0) * 0.14;
            col += mix(u.primary.rgb, u.secondary.rgb, uv.y) * rimGlow;

            float vignette = smoothstep(1.25, 0.2, dist);
            col *= (0.78 + 0.22 * vignette);

            // Premultiplied alpha for crisp macOS transparent panel compositing.
            float finalAlpha = clamp(u.glassTint.a + coreFalloff * 0.08 + rimGlow * 0.35, 0.68, 0.86);
            return float4(col * finalAlpha, finalAlpha);
        }
        """
    }
}

// MARK: - Graceful SwiftUI Canvas Fallback

fileprivate struct FallbackReactorCanvasView: View {
    let theme: HUDTheme
    let activityIntensity: Double
    let isPulseActive: Bool

    var body: some View {
        let interval = (isPulseActive || activityIntensity > 0.25) ? (1.0 / 15.0) : (1.0 / 8.0)
        TimelineView(.animation(minimumInterval: interval)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let speed = 1.0 + activityIntensity * 1.1 + (isPulseActive ? 0.7 : 0.0)
                let phase = t * speed

                let rect = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(colors: [
                            theme.glassTint.opacity(0.92),
                            Color(red: 0.015, green: 0.022, blue: 0.038).opacity(0.84)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.44)
                let maxDim = max(size.width, size.height)

                // Soft radial reactor core glow
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - maxDim * 0.45,
                        y: center.y - maxDim * 0.45,
                        width: maxDim * 0.9,
                        height: maxDim * 0.9
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            theme.primary.opacity(0.16 + activityIntensity * 0.1),
                            theme.secondary.opacity(0.08),
                            .clear
                        ]),
                        center: center,
                        startRadius: 2,
                        endRadius: maxDim * 0.45
                    )
                )

                // Micro-grid
                let step: CGFloat = 28
                let driftX = CGFloat((phase * 4.0).truncatingRemainder(dividingBy: Double(step)))
                let driftY = CGFloat((phase * 2.5).truncatingRemainder(dividingBy: Double(step)))
                var gridPath = Path()
                var x = -step + driftX
                while x < size.width + step {
                    gridPath.move(to: CGPoint(x: x, y: 0))
                    gridPath.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y = -step + driftY
                while y < size.height + step {
                    gridPath.move(to: CGPoint(x: 0, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(gridPath, with: .color(theme.primary.opacity(0.06)), lineWidth: 0.6)

                // Horizontal radar scanline sweep
                let sweepNorm = (phase * 0.15).truncatingRemainder(dividingBy: 1.0)
                let sweepY = size.height * CGFloat(sweepNorm)
                let sweepRect = CGRect(x: 0, y: sweepY - 12, width: size.width, height: 24)
                context.fill(
                    Path(sweepRect),
                    with: .linearGradient(
                        Gradient(colors: [.clear, theme.accent.opacity(0.09), .clear]),
                        startPoint: CGPoint(x: 0, y: sweepRect.minY),
                        endPoint: CGPoint(x: 0, y: sweepRect.maxY)
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}
