//
//  ImmersiveView.swift
//  RealityKitShowImageOriginV1
//
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    @State
    private var triangleModel:CreateDynamicTriangle = .init()
    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                let triangle = try! await triangleModel.triangleEntity()
                content.add(triangle)
                triangle.position = .init(x: 0, y: 0, z: -1)
                
                let controlPoints = triangleModel.generateControlPoints()
                for controlPoint in controlPoints {
                    content.add(controlPoint)
                    controlPoint.position += .init(x: 0, y: 0, z: -1)
                }
               
                // Put skybox here.  See example in World project available at
                // https://developer.apple.com/
            }
        }
        .gesture(DragGesture().targetedToAnyEntity().onChanged({ gestureValue in
            let location:SIMD3<Float> = gestureValue.convert(gestureValue.location3D, from: .local, to:.scene)
            gestureValue.entity.setPosition(location, relativeTo: nil)
            switch gestureValue.entity {
            case triangleModel.controlPoint0://控制三角形的最上方顶点
                triangleModel.updateVertexPosition(index: 0, newPosition: triangleModel.toLocalPosition(globalPosition: location))
            case triangleModel.controlPoint1:
                triangleModel.updateVertexPosition(index: 1, newPosition: triangleModel.toLocalPosition(globalPosition: location))
            case triangleModel.controlPoint2:
                triangleModel.updateVertexPosition(index: 2, newPosition: triangleModel.toLocalPosition(globalPosition: location))
            default:
                break
            }
        }))
        .onAppear {
            // 在这里更新顶点位置
            triangleModel.updateVertexPosition(index:2, newPosition: [Float(0),1, 0])
        }
    }
}


struct MyVertex {
    var position: SIMD3<Float> = .zero
    var color: UInt32 = .zero
    var texCoord: SIMD2<Float> = .zero  // 添加纹理坐标
}

extension MyVertex {
    static var vertexAttributes: [LowLevelMesh.Attribute] = [
        .init(semantic: .position, format: .float3, offset: MemoryLayout<Self>.offset(of: \.position)!),
        .init(semantic: .color, format: .uchar4Normalized_bgra, offset: MemoryLayout<Self>.offset(of: \.color)!) ,
        .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Self>.offset(of: \.texCoord)!)  // 添加纹理坐标属性
    ]


    static var vertexLayouts: [LowLevelMesh.Layout] = [
        .init(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride)
    ]


    static var descriptor: LowLevelMesh.Descriptor {
        var desc = LowLevelMesh.Descriptor()
        desc.vertexAttributes = MyVertex.vertexAttributes
        desc.vertexLayouts = MyVertex.vertexLayouts
        desc.indexType = .uint32
        return desc
    }
}
@MainActor
@Observable
class CreateDynamicTriangle {

    private var lowLevelMesh: LowLevelMesh?
    private var triangleEntity: Entity?
    var controlPoint0: Entity?
    let controlPoint0InitPosition:SIMD3<Float> = [-1, -1, 0]
    var controlPoint1: Entity?
    let controlPoint1InitPosition:SIMD3<Float> = [ 1, -1, 0]
    var controlPoint2: Entity?
    let controlPoint2InitPosition:SIMD3<Float> = [ 0,  1, 0]

    func triangleMesh() throws -> LowLevelMesh {
        var desc = MyVertex.descriptor
        desc.vertexCapacity = 3  // 改为3个顶点
        desc.indexCapacity = 3   // 改为3个索引

        let mesh = try LowLevelMesh(descriptor: desc)

    
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: MyVertex.self)
            vertices[0] = MyVertex(position: controlPoint0InitPosition, color: 0xFF00FF00, texCoord: [0, 1])
            vertices[1] = MyVertex(position: controlPoint1InitPosition, color: 0xFFFF0000, texCoord: [1, 1])
            vertices[2] = MyVertex(position: controlPoint2InitPosition, color: 0xFF0000FF, texCoord: [0.5, 0])
        }

        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            indices[0] = 0
            indices[1] = 1
            indices[2] = 2
        }

        let meshBounds = BoundingBox(min: [-1, -1, 0], max: [1, 1, 0])
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: 3,  // 更新为3个索引
                topology: .triangle,
                bounds: meshBounds
            )
        ])

        self.lowLevelMesh = mesh
        return mesh
    }
    

    func generateControlPoints() -> [Entity] {
        let controlPoint0 = generateControlPoint()
        let controlPoint1 = generateControlPoint()
        let controlPoint2 = generateControlPoint()
        let controlPoints: [Entity] = [controlPoint0, controlPoint1, controlPoint2]
        controlPoint0.position = controlPoint0InitPosition
        controlPoint1.position = controlPoint1InitPosition
        controlPoint2.position = controlPoint2InitPosition
        self.controlPoint0 = controlPoint0
        self.controlPoint1 = controlPoint1
        self.controlPoint2 = controlPoint2
        return controlPoints
    }

    private
    func generateControlPoint() -> Entity {
        let sphere = try! MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: .red, isMetallic: false)
        let entity = Entity()
        entity.components.set(ModelComponent(mesh: sphere, materials: [material]))
        // CollisionComponent
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.1)/*触摸范围更大，更好抓握*/]))
        //InputTargetComponent
        entity.components.set(InputTargetComponent())
        return entity
    }

    func triangleEntity() async throws -> Entity {
        let lowLevelMesh = try triangleMesh()  // 调用新的triangleMesh()方法
        let resource = try await MeshResource(from: lowLevelMesh)

        // 创建纹理材质
        let uiImage:UIImage = .init(data: try! Data(contentsOf: Bundle.main.url(forResource: "amsler-grid-image.jpg", withExtension: "")!))!
            let cgImage:CGImage = uiImage.cgImage!
            
        var material = await UnlitMaterial(texture: try .init(image: cgImage, options: .init(semantic: nil)))
        material.faceCulling = .none
        let modelComponent = ModelComponent(mesh: resource, materials: [material])

        let entity = Entity()
        entity.name = "Triangle"  // 更新名称
        entity.components.set(modelComponent)
        self.triangleEntity = entity
        return entity
    }
    func toLocalPosition(globalPosition:SIMD3<Float>) -> SIMD3<Float> {
        guard let triangleEntity else {
            fatalError("没有找到实体")
        }
        return triangleEntity.convert(position: globalPosition, from: nil)
    }
    func updateVertexPosition(index: Int, newPosition: SIMD3<Float>) {
        guard let mesh = lowLevelMesh else { return }
        
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: MyVertex.self)
            vertices[index].position = newPosition
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
