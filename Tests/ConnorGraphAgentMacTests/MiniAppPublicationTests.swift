import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import ConnorGraphAppSupport
import ConnorGraphBase
@testable import ConnorGraphAgentMac

private actor MiniAppPublicationCredentials:CloudKnowledgeCredentialProvider {
    var token="reviewed-account"
    func accessToken()async throws->String{token}
    func change(){token="another-account"}
}
private actor MiniAppPublicationTransport:ConnorBackendHTTPTransport {
    var revision=0,publishCount=0
    var lastPublish:Data?
    func data(for request:URLRequest)async throws->(Data,URLResponse){
        let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
        let tool=body["tool"] as? String ?? ""
        if tool=="base.publish"{lastPublish=request.httpBody;publishCount+=1;revision+=1}
        let data:[String:Any]=tool=="base.app.list" ? ["items":[],"page":1,"limit":20,"total":0,"hasMore":false] : ["published":revision>0,"revision":revision,"visibility":"public"]
        return (try JSONSerialization.data(withJSONObject:["ok":true,"data":data]),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    }
}
final class MiniAppPublicationTests:XCTestCase {
    @MainActor func testRecordOptInAndReviewedCredentialsProtectPrivateData()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let library=try BaseLibraryStore(directory:root);defer{library.close()}
        _ = try library.createApp(manifest:["appID":"demo","name":"Demo"],schemaObject:["tables":[["name":"entries","fields":[["name":"body","type":"text"]]]]],guide:["authoring":["summary":"make"],"usage":["summary":"use"]])
        let store=try library.openStore(appID:"demo");defer{store.close()}
        try store.insert(id:"rec_1",table:"entries",values:["body":.string("private record")])
        _ = try library.syncAppKey(appID:"demo")
        let credentials=MiniAppPublicationCredentials(),transport=MiniAppPublicationTransport()
        let cloud=BaseCloudAPIClient(baseURL:URL(string:"https://example.invalid")!,transport:transport,credentials:credentials)
        let model=MiniAppFeatureModel(library:library,cloudClient:cloud)
        await model.inspectPublication(appID:"demo")
        await model.changePublication(appID:"demo",visibility:"public",includeData:false)
        var payload=try JSONSerialization.jsonObject(with:await transport.lastPublish!) as! [String:Any]
        var args=payload["args"] as! [String:Any]
        XCTAssertTrue(((args["data"] as! [String:Any])["tables"] as! [String:Any]).isEmpty)
        XCTAssertNil(args["keys"])
        await model.changePublication(appID:"demo",visibility:"public",includeData:true)
        payload=try JSONSerialization.jsonObject(with:await transport.lastPublish!) as! [String:Any];args=payload["args"] as! [String:Any]
        XCTAssertEqual((((args["data"] as! [String:Any])["tables"] as! [String:Any])["entries"] as! [[String:Any]]).first?["body"] as? String,"private record")
        XCTAssertNil(args["keys"])
        let before=await transport.publishCount
        await credentials.change()
        await model.changePublication(appID:"demo",visibility:"public",includeData:true)
        let after=await transport.publishCount
        XCTAssertEqual(before,after,"private records must not be published using a later account")
        XCTAssertTrue(model.publicationStatus.contains("未完成"))
    }
}
