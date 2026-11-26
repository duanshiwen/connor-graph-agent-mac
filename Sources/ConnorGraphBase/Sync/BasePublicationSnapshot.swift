import Foundation
extension BaseLibraryStore {
    /// Freeze one publication. A definition-only publication never scans business rows or exports keys.
    public func publicationSnapshot(appID:String,includeData:Bool)throws->Data {
        let operation=beginLocalOperation();defer{operation.finish()}
        if try isGuideOutOfSync(appID:appID){throw BaseError(code:.guideOutOfSync,message:"指南与包签名不同步",hint:"请先同批更新指南")}
        let payload:[String:Any]
        if includeData {let snapshot=try accountSnapshot(appID:appID);payload=["package":snapshot["package"] ?? [:],"data":snapshot["data"] ?? [:]]}
        else {guard let package=try packageDictionary(appID:appID) else {throw BaseError.notFound(appID)};payload=["package":package,"data":["tables":[:]]]}
        operation.finish()
        return try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys])
    }
}
