//
//  Scene.swift
//  RayTracingExample
//
//  Created by David Crooks on 08/09/2020.
//  Copyright © 2020 David Crooks. All rights reserved.
//

import Foundation
import simd

enum TriangleMask:Int {
    case geometry = 1
    case light = 2
}

class Scene
{
    var vertices:[vector_float3] = []
    var normals:[vector_float3] = []
    var colors:[vector_float3] = []
    var masks:[UInt32] = []
    
    func createCubesScene() {
        var transform = matrix4x4_translation(0.0, 1.0, 0.0) * matrix4x4_scale(sx: 0.5, sy: 1.98, sz: 0.5)
        
        // Light source
        createCube(faceMask: FaceMask.positive_Y, vector_float3: vector3(1.0, 1.0, 1.0), transform: transform, inwardNormals: true,
                   triangleMask: TriangleMask.light)
        
        transform = matrix4x4_translation(0.0, 1.0, 0.0) * matrix4x4_scale(sx: 2.0, sy: 2.0, sz: 2.0);
                
                // Top, bottom, and back walls
        createCube(faceMask: [FaceMask.negative_Y ,FaceMask.positive_Y , FaceMask.negative_Z], vector_float3: vector3(0.725, 0.71, 0.68), transform: transform, inwardNormals: true, triangleMask: TriangleMask.geometry);
                
                // Left wall
        createCube(faceMask: FaceMask.negative_X, vector_float3: vector3(0.63, 0.065, 0.05), transform: transform, inwardNormals: true,
                   triangleMask: TriangleMask.geometry);
                
                // Right wall
        createCube(faceMask: FaceMask.positive_X, vector_float3: vector3(0.14, 0.45, 0.091), transform: transform, inwardNormals: true,
                   triangleMask: TriangleMask.geometry);
        
        transform = matrix4x4_translation(0.3275, 0.3, 0.3725) *
                    matrix4x4_rotation(radians: -0.3, axis: vector3(0.0, 1.0, 0.0)) *
                    matrix4x4_scale(sx: 0.6, sy: 0.6, sz: 0.6);
           
           // Short box
        createCube(faceMask: FaceMask.all, vector_float3: vector3(0.725, 0.71, 0.68), transform: transform, inwardNormals: false,
               triangleMask: TriangleMask.geometry);
           
        transform = matrix4x4_translation(-0.335, 0.6, -0.29) *
                    matrix4x4_rotation(radians: 0.3, axis: vector3(0.0, 1.0, 0.0)) *
                    matrix4x4_scale(sx: 0.6, sy: 1.2, sz: 0.6);
           
           // Tall box
        createCube(faceMask: FaceMask.all, vector_float3: vector3(0.725, 0.71, 0.68), transform: transform, inwardNormals: false,
               triangleMask: TriangleMask.geometry);
        
    }
    
    func createCube(
           faceMask:FaceMask,
           vector_float3 color:SIMD3<Float>,
            transform:matrix_float4x4,
           inwardNormals:Bool,
                       triangleMask:TriangleMask
       )
    {
        
        let unitCubeVertices:[SIMD3<Float>] =  [
                                                SIMD3<Float>(-0.5, -0.5, -0.5),
                                                SIMD3<Float>( 0.5, -0.5, -0.5),
                                                SIMD3<Float>(-0.5,  0.5, -0.5),
                                                SIMD3<Float>( 0.5,  0.5, -0.5),
                                                SIMD3<Float>(-0.5, -0.5,  0.5),
                                                SIMD3<Float>( 0.5, -0.5,  0.5),
                                                SIMD3<Float>(-0.5,  0.5,  0.5),
                                                SIMD3<Float>( 0.5,  0.5,  0.5)
                                                ]
        
        let cubeVertices = unitCubeVertices
                                    .map{ transform * vector4($0.x, $0.y, $0.z, 1.0) }
                                    .map{ SIMD3<Float>($0.x, $0.y, $0.z) }
        
        
        if faceMask.contains(.negative_X)
        {
            createCubeFace( cubeVertices: cubeVertices, color: color, i0: 0, i1: 4, i2: 6, i3: 2, inwardNormals: inwardNormals, triangleMask: triangleMask)
        }

        if faceMask.contains(.positive_X)
        {
            createCubeFace( cubeVertices: cubeVertices, color: color, i0: 1, i1: 3, i2: 7, i3: 5, inwardNormals: inwardNormals, triangleMask: triangleMask)
        }

        if faceMask.contains(.negative_Y)
        {
            createCubeFace( cubeVertices: cubeVertices, color: color, i0: 0, i1: 1, i2: 5, i3: 4, inwardNormals: inwardNormals, triangleMask: triangleMask)
        }

        if faceMask.contains(.positive_Y)
        {
            createCubeFace( cubeVertices: cubeVertices, color: color, i0: 2, i1: 6, i2: 7, i3: 3, inwardNormals: inwardNormals, triangleMask: triangleMask)
        }

        if faceMask.contains(.negative_Z)
        {
            createCubeFace( cubeVertices: cubeVertices, color: color, i0: 0, i1: 2, i2: 3, i3: 1, inwardNormals: inwardNormals, triangleMask: triangleMask)
        }

        if faceMask.contains(.positive_Z)
        {
            createCubeFace( cubeVertices: cubeVertices, color: color, i0: 4, i1: 5, i2: 7, i3: 6, inwardNormals: inwardNormals, triangleMask: triangleMask)
        }

    }
    
    func createCubeFace(cubeVertices:[SIMD3<Float>],
                            color:SIMD3<Float>,
                                i0:Int,
                                i1:Int,
                                i2:Int,
                                i3:Int,
                                inwardNormals:Bool,
                                triangleMask:TriangleMask)
    {
        let v0 = cubeVertices[i0]
        let v1 = cubeVertices[i1]
        let v2 = cubeVertices[i2]
        let v3 = cubeVertices[i3]
        
        var n0 = getTriangleNormal(v0: v0, v1: v1, v2: v2)
        var n1 = getTriangleNormal(v0: v0, v1: v2, v2: v3)
        
        if inwardNormals {
            n0 = -n0
            n1 = -n1
        }
        
        vertices.append(v0)
        vertices.append(v1)
        vertices.append(v2)
        vertices.append(v0)
        vertices.append(v2)
        vertices.append(v3)
        
        for _ in 0..<3 {
            normals.append(n0)
        }
        
        for _ in 0..<3 {
            normals.append(n1)
        }
        
        for _ in 0..<6 {
            colors.append(color)
        }
        
        for _ in 0..<2 {
            masks.append(UInt32(triangleMask.rawValue))
        }
    }
}
    
    
    







