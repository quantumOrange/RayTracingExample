//
//  Renderer.swift
//  RayTracingExample
//
//  Created by David Crooks on 06/09/2020.
//  Copyright © 2020 David Crooks. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd
import MetalPerformanceShaders

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

class Renderer:NSObject,MTKViewDelegate {
    
    let raytracer: RaytracerRenderer
    
    init?(metalKitView: MTKView) {
        guard let raytracer = RaytracerRenderer(metalKitView: metalKitView) else { return nil }
        self.raytracer = raytracer
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        raytracer.mtkView(view, drawableSizeWillChange: size)
    }
    
    func draw(in view: MTKView) {
        raytracer.draw(in: view)
    }
}

class RaytracerRenderer  {
    
    var view:MTKView
    public let device: MTLDevice
    var commandQueue: MTLCommandQueue
    var library:MTLLibrary
    
    var accelerationStructure:MPSTriangleAccelerationStructure!
    var intersector:MPSRayIntersector!
    
    var vertexPositionBuffer:MTLBuffer!
    var vertexNormalBuffer:MTLBuffer!
    var vertexColorBuffer:MTLBuffer!
    var rayBuffer:MTLBuffer!
    var shadowRayBuffer:MTLBuffer!
    var intersectionBuffer:MTLBuffer!
    var uniformBuffer:MTLBuffer!
    var triangleMaskBuffer:MTLBuffer!
    
    var rayPipeline:MTLComputePipelineState!
    var shadePipeline:MTLComputePipelineState!
    var shadowPipeline:MTLComputePipelineState!
    var accumulatePipeline:MTLComputePipelineState!
    var copyPipeline:MTLRenderPipelineState!
    
    var renderTargets_0:MTLTexture!
    var accumulationTargets_0:MTLTexture!
    var renderTargets_1:MTLTexture!
    var accumulationTargets_1:MTLTexture!
    
    var randomTexture:MTLTexture!
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var size:CGSize = CGSize.zero
    var uniformBufferOffset:Int = 0
    var uniformBufferIndex:Int = 0
    var uniformBufferAddress: UnsafeMutableRawPointer!
    
    var scene:Scene

    let rayStride = 48
    let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride;
    
    var frameIndex = 0
    
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue(),
            let lib = device.makeDefaultLibrary()
                                                else { return nil }
        
        self.view = metalKitView
        view.colorPixelFormat = MTLPixelFormat.rgba16Float
        view.sampleCount = 1
        view.drawableSize = view.frame.size
        
        self.commandQueue = queue
        self.library = lib
        
        scene = Scene()
        scene.createCubesScene()
        guard let _ = try? loadMetal() else { return nil }
        
    }
    
    func loadMetal() throws {
        try createPipelines()
        createBuffers()
        createIntersector()
    }
    
    func createPipelines() throws {
        
        let computeDescriptor = MTLComputePipelineDescriptor()
        computeDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
        
        computeDescriptor.computeFunction = library.makeFunction(name: "rayKernel")
        rayPipeline =  try device.makeComputePipelineState(descriptor: computeDescriptor, options: MTLPipelineOption(rawValue: 0), reflection: nil)
        
        computeDescriptor.computeFunction = library.makeFunction(name: "shadeKernel")
        shadePipeline =  try device.makeComputePipelineState(descriptor: computeDescriptor, options: MTLPipelineOption(rawValue: 0), reflection: nil)
        
        computeDescriptor.computeFunction = library.makeFunction(name: "shadowKernel")
        shadowPipeline =  try device.makeComputePipelineState(descriptor: computeDescriptor, options: MTLPipelineOption(rawValue: 0), reflection: nil)
       
        computeDescriptor.computeFunction = library.makeFunction(name: "accumulateKernel")
        
        computeDescriptor.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
        computeDescriptor.computeFunction = library.makeFunction(name: "accumulateKernel")
        accumulatePipeline = try device.makeComputePipelineState(descriptor: computeDescriptor, options: MTLPipelineOption(rawValue: 0), reflection: nil)
        
        let renderDescriptor = MTLRenderPipelineDescriptor()
        renderDescriptor.sampleCount = view.sampleCount
        renderDescriptor.vertexFunction = library.makeFunction(name:"copyVertex")
        renderDescriptor.fragmentFunction = library.makeFunction(name:"copyFragment")
        renderDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        copyPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)
    }
    
    func createBuffers()  {
        
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        
        #if os(iOS)
            let options = MTLResourceOptions.storageModeShared
        #elseif os(OSX)
            let options = MTLResourceOptions.storageModeManaged
        #endif
        
        
        guard   let _uniformBuffer = device.makeBuffer(length: uniformBufferSize, options: options),
                let _vertexPositionBuffer = device.makeBuffer(length: scene.vertices.byteLength, options: options),
                let _vertexColorBuffer = device.makeBuffer(length:    scene.colors.byteLength, options: options),
                let _vertexNormalBuffer = device.makeBuffer(length:   scene.normals.byteLength, options: options),
                let _triangleMaskBuffer  = device.makeBuffer(length:  scene.masks.byteLength, options: options)
                                                                                                            else { return }

        uniformBuffer           = _uniformBuffer
        vertexPositionBuffer    = _vertexPositionBuffer
        vertexColorBuffer       = _vertexColorBuffer
        vertexNormalBuffer      = _vertexNormalBuffer
        triangleMaskBuffer      = _triangleMaskBuffer
        
        vertexPositionBuffer.contents().copyMemory(from:scene.vertices, byteCount:scene.vertices.byteLength)
        vertexColorBuffer.contents().copyMemory(from:scene.colors, byteCount:scene.colors.byteLength)
        vertexNormalBuffer.contents().copyMemory(from:scene.normals, byteCount:scene.normals.byteLength)
        triangleMaskBuffer.contents().copyMemory(from:scene.masks, byteCount:scene.masks.byteLength)
        
        #if os(OSX)
        vertexPositionBuffer.didModifyRange( 0..<vertexPositionBuffer.length )
        vertexColorBuffer.didModifyRange(    0..<vertexColorBuffer.length    )
        vertexNormalBuffer.didModifyRange(   0..<vertexNormalBuffer.length   )
        triangleMaskBuffer.didModifyRange(   0..<triangleMaskBuffer.length   )
        #endif
        
    }
    
    func createIntersector() {
        intersector = MPSRayIntersector(device: device)
       
        //MPSRayDataType.originMaskDirectionMaxDistance
        intersector.rayDataType     =  MPSRayDataType.originMaskDirectionMaxDistance
        intersector.rayStride       =  rayStride
        intersector.rayMaskOptions  =  MPSRayMaskOptions.primitive
        
        accelerationStructure = MPSTriangleAccelerationStructure(device: device)
        accelerationStructure.vertexBuffer  =  vertexPositionBuffer;
        accelerationStructure.maskBuffer    = triangleMaskBuffer;
        accelerationStructure.triangleCount = scene.vertices.count / 3
        
        accelerationStructure.rebuild()
    }
    
    
    func updateUnifroms() {
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        
        uniformBufferAddress = uniformBuffer.contents().advanced(by:uniformBufferOffset)
        
        let uniforms = uniformBufferAddress.assumingMemoryBound(to: Uniforms.self)

        uniforms.pointee.camera.position = vector3(0.0, 1.0, 3.38)
        uniforms.pointee.camera.forward = vector3(0.0, 0.0, -1.0)
        uniforms.pointee.camera.right = vector3(1.0, 0.0, 0.0)
        uniforms.pointee.camera.up = vector3(0.0, 1.0, 0.0)
        uniforms.pointee.light.position = vector3(0.0, 1.98, 0.0)
        uniforms.pointee.light.forward = vector3(0.0, -1.0, 0.0)
        uniforms.pointee.light.right = vector3(0.25, 0.0, 0.0)
        uniforms.pointee.light.up = vector3(0.0, 0.0, 0.25)
        uniforms.pointee.light.color = vector3(4.0, 4.0, 4.0)
        
        let fieldOfView = 45.0 * (Float.pi / 180.0)
        let aspectRatio = Float(size.width / size.height)
        let imagePlaneHeight = tanf(fieldOfView / 2.0)
        let imagePlaneWidth = aspectRatio * imagePlaneHeight
        
        frameIndex += 1
        
        uniforms.pointee.camera.right *= imagePlaneWidth
        uniforms.pointee.camera.up *= imagePlaneHeight
       
        uniforms.pointee.width = UInt32(size.width)
        uniforms.pointee.height = UInt32(size.height)
        
        
        uniforms.pointee.frameIndex = UInt32(frameIndex)
        
        #if os(OSX)
        let range = uniformBufferOffset..<uniformBufferOffset+alignedUniformsSize;
        uniformBuffer.didModifyRange( range)
        #endif
        
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
    }
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            updateUnifroms()
            let width = Int(size.width)
            let height = Int(size.height)
            
            
            // We will launch a rectangular grid of threads on the GPU to generate the rays. Threads are launched in
            // groups called "threadgroups". We need to align the number of threads to be a multiple of the threadgroup
            // size. We indicated when compiling the pipeline that the threadgroup size would be a multiple of the thread
            // execution width (SIMD group size) which is typically 32 or 64 so 8x8 is a safe threadgroup size which
            // should be small to be supported on most devices. A more advanced application would choose the threadgroup
            // size dynamically.
            let threadsPerThreadgroup = MTLSize(width: 8, height: 8, depth: 1);
            let threadgroups = MTLSize(width: (width  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
                                       height: (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                                       depth: 1);
            
            var computeEncoder = commandBuffer.makeComputeCommandEncoder()!
            
            // 1) Generate rays
            computeEncoder.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: 0)
            computeEncoder.setBuffer(rayBuffer,offset: 0,index: 1)
            
            computeEncoder.setTexture(randomTexture, index: 0)
            computeEncoder.setTexture(renderTargets_0, index: 1)
            
            computeEncoder.setComputePipelineState(rayPipeline)
            
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            
            
            computeEncoder.endEncoding()
            
            // Bounce the rays about a few times
            for i in 0..<3 {
                intersector.intersectionDataType = MPSIntersectionDataType.distancePrimitiveIndexCoordinates
                
                intersector.encodeIntersection( commandBuffer: commandBuffer,
                                                intersectionType: MPSIntersectionType.nearest,
                                                rayBuffer: rayBuffer,
                                                rayBufferOffset: 0,
                                                intersectionBuffer: intersectionBuffer,
                                                intersectionBufferOffset: 0,
                                                rayCount: width * height,
                                                accelerationStructure: accelerationStructure)
               
                computeEncoder = commandBuffer.makeComputeCommandEncoder()!
                
                
            
                computeEncoder.setBuffer(uniformBuffer      , offset:uniformBufferOffset,  index:0)
                computeEncoder.setBuffer(rayBuffer          , offset:0                  ,  index:1)
                computeEncoder.setBuffer(shadowRayBuffer    , offset:0                  ,  index:2)
                computeEncoder.setBuffer(intersectionBuffer , offset:0                  ,  index:3)
                computeEncoder.setBuffer(vertexColorBuffer  , offset:0                  ,  index:4)
                computeEncoder.setBuffer(vertexNormalBuffer , offset:0                  ,  index:5)
                computeEncoder.setBuffer(triangleMaskBuffer , offset:0                  ,  index:6)
                
                var bounce = i
                computeEncoder.setBytes(&bounce, length:MemoryLayout<Int>.size , index: 7) // ???  wtf?
                
                computeEncoder.setTexture(randomTexture,   index: 0)
                computeEncoder.setTexture(renderTargets_0, index: 1)
                
                computeEncoder.setComputePipelineState(shadePipeline)
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()
                
                /* *** shadows **** */
                
                intersector.intersectionDataType = MPSIntersectionDataType.distance
                 
                intersector.encodeIntersection(  commandBuffer: commandBuffer,
                                                 intersectionType: MPSIntersectionType.any,
                                                 rayBuffer: shadowRayBuffer,
                                                 rayBufferOffset: 0,
                                                 intersectionBuffer: intersectionBuffer,
                                                 intersectionBufferOffset: 0,
                                                 rayCount: width * height,
                                                 accelerationStructure: accelerationStructure)
                
                computeEncoder = commandBuffer.makeComputeCommandEncoder()!
                 
                computeEncoder.setBuffer(  uniformBuffer,       offset:uniformBufferOffset  , index:0 )
                computeEncoder.setBuffer(  shadowRayBuffer,     offset:0                    , index:1 )
                computeEncoder.setBuffer(  intersectionBuffer,  offset:0                    , index:2 )
                computeEncoder.setTexture( renderTargets_0,     index:0 )
                computeEncoder.setTexture( renderTargets_1,     index:1 )
                
                computeEncoder.setComputePipelineState(shadowPipeline)
                computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()
                
                swap(&renderTargets_0,&renderTargets_1)
               
            }
            /* *** acumulate **** */
            computeEncoder = commandBuffer.makeComputeCommandEncoder()!
                    
            computeEncoder.setBuffer(  uniformBuffer,       offset:uniformBufferOffset  , index:0 )

            computeEncoder.setTexture( renderTargets_0,     index:0 )
            computeEncoder.setTexture( accumulationTargets_0,     index:1 )
            computeEncoder.setTexture( accumulationTargets_1,     index:2 )

            computeEncoder.setComputePipelineState(accumulatePipeline)
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            computeEncoder.endEncoding()

            swap(&accumulationTargets_0,&accumulationTargets_1)
            
            
            let renderPassDescriptor = view.currentRenderPassDescriptor

            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                renderEncoder.setRenderPipelineState(copyPipeline)
                renderEncoder.setFragmentTexture(accumulationTargets_1, index: 0)
                // Draw a quad which fills the screen
                renderEncoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 6)
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        self.size = size
        
        let rayCount = Int(size.width)*Int(size.height)
        let options = MTLResourceOptions.storageModePrivate
        
        rayBuffer          = device.makeBuffer(length: rayStride * rayCount, options: options)!
        shadowRayBuffer    = device.makeBuffer(length: rayStride * rayCount, options: options)!
        intersectionBuffer = device.makeBuffer(length: intersectionStride * rayCount, options: options)!
        
        let renderTargetDescriptor = MTLTextureDescriptor()
     
        renderTargetDescriptor.pixelFormat = MTLPixelFormat.rgba32Float
        renderTargetDescriptor.textureType =  MTLTextureType.type2D
        renderTargetDescriptor.width = Int(size.width)
        renderTargetDescriptor.height = Int(size.height)
        
        renderTargetDescriptor.usage = [ MTLTextureUsage.shaderRead , MTLTextureUsage.shaderWrite ]
        
        renderTargets_0 = device.makeTexture(descriptor:renderTargetDescriptor)!
        accumulationTargets_0 = device.makeTexture(descriptor:renderTargetDescriptor)!
        renderTargets_1 = device.makeTexture(descriptor:renderTargetDescriptor)!
        accumulationTargets_1 = device.makeTexture(descriptor:renderTargetDescriptor)!
        
        
        let randomFloats:[Float32] = (0..<rayCount)
                                        .flatMap{ _ in [Float.random(in: 0..<1.0),Float.random(in: 0..<0.5),0.0,1.0] }
                                    
        accumulationTargets_1.replace(region: MTLRegionMake2D(0, 0, Int(size.width), Int(size.height)), mipmapLevel: 0, withBytes: randomFloats, bytesPerRow: 4*MemoryLayout<Float32>.size * Int(size.width))
        accumulationTargets_0.replace(region: MTLRegionMake2D(0, 0, Int(size.width), Int(size.height)), mipmapLevel: 0, withBytes: randomFloats, bytesPerRow: 4*MemoryLayout<Float32>.size * Int(size.width))
        
        
        renderTargetDescriptor.pixelFormat = MTLPixelFormat.r32Uint
        renderTargetDescriptor.usage = MTLTextureUsage.shaderRead
        
        #if os(iOS)
            renderTargetDescriptor.storageMode = MTLStorageMode.shared
        #elseif os(OSX)
            renderTargetDescriptor.storageMode = MTLStorageMode.managed
        #endif
        
        // Generate a texture containing a random integer value for each pixel. This value
        // will be used to decorrelate pixels while drawing pseudorandom numbers from the
        // Halton sequence.
        randomTexture = device.makeTexture(descriptor:renderTargetDescriptor)!
        
        let range:Range< UInt32> = 0..<(1024 * 1024)
        let randomValues = (0..<rayCount).map { _ in UInt32.random(in: range) }
            
        randomTexture.replace(region: MTLRegionMake2D(0, 0, Int(size.width), Int(size.height)), mipmapLevel: 0, withBytes: randomValues, bytesPerRow: MemoryLayout<UInt32>.size * Int(size.width))
        
        frameIndex = 0
    }
}


