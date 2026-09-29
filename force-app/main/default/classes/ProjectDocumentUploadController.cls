public with sharing class ProjectDocumentUploadController {

    // Same OneDrive account CreateOneDriveFoldersQueueable creates the project folders in
    private static final String DRIVE_USER = 'isha.raj@utilitarianlabs.com';
    private static final String GRAPH_ITEMS = 'https://graph.microsoft.com/v1.0/users/' + DRIVE_USER + '/drive/items/';
    private static final Set<String> ALLOWED_EXTENSIONS = new Set<String>{ 'pdf', 'jpg', 'jpeg', 'png', 'mp4' };

    private static String accessToken;

    public class DocumentFolder {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean hasFolder;
        @AuraEnabled public Integer fileCount;
    }

    public class ChunkResult {
        @AuraEnabled public Boolean complete;
        @AuraEnabled public String itemId;
    }

    public class UploadResult {
        @AuraEnabled public Id subDocumentId;
        @AuraEnabled public String fileUrl;
        @AuraEnabled public Boolean isPublic;
    }

    @AuraEnabled(cacheable=true)
    public static List<DocumentFolder> getProjectDocuments(Id projectId) {
        Map<Id, Integer> fileCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Document__c docId, COUNT(Id) total
            FROM Sub_Document__c
            WHERE Document__r.Project__c = :projectId
            WITH SYSTEM_MODE
            GROUP BY Document__c
        ]) {
            fileCounts.put((Id) ar.get('docId'), (Integer) ar.get('total'));
        }

        List<DocumentFolder> folders = new List<DocumentFolder>();
        for (Document__c doc : [
            SELECT Id, Name, Status__c, Document_Id__c
            FROM Document__c
            WHERE Project__c = :projectId
            WITH SYSTEM_MODE
            ORDER BY Name
        ]) {
            DocumentFolder folder = new DocumentFolder();
            folder.id = doc.Id;
            folder.name = doc.Name;
            folder.status = doc.Status__c;
            folder.hasFolder = String.isNotBlank(doc.Document_Id__c);
            folder.fileCount = fileCounts.containsKey(doc.Id) ? fileCounts.get(doc.Id) : 0;
            folders.add(folder);
        }
        return folders;
    }

    // Starts a OneDrive upload session inside the Document's folder; the file itself is sent with uploadChunk.
    @AuraEnabled
    public static String createUploadSession(Id documentId, String fileName) {
        String cleanName = cleanFileName(fileName);
        Document__c doc = getFolderDocument(documentId);

        HttpRequest req = graphRequest('POST', GRAPH_ITEMS + doc.Document_Id__c + ':/' + encodePathSegment(cleanName) + ':/createUploadSession');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'item' => new Map<String, Object>{ '@microsoft.graph.conflictBehavior' => 'rename' }
        }));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw graphError('Could not start the upload in OneDrive', res);
        }
        return (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('uploadUrl');
    }

    // Sends one byte range of the file. OneDrive answers 202 until the last range, then 200/201 with the new item.
    @AuraEnabled
    public static ChunkResult uploadChunk(String uploadUrl, String base64Chunk, Long startByte, Long endByte, Long totalSize) {
        if (!isOneDriveUploadUrl(uploadUrl)) {
            throw userError('Invalid upload session.');
        }
        HttpRequest req = new HttpRequest();
        req.setMethod('PUT');
        req.setEndpoint(uploadUrl);
        req.setHeader('Content-Range', 'bytes ' + startByte + '-' + (endByte - 1) + '/' + totalSize);
        req.setBodyAsBlob(EncodingUtil.base64Decode(base64Chunk));
        req.setTimeout(120000);
        HttpResponse res = new Http().send(req);

        ChunkResult result = new ChunkResult();
        if (res.getStatusCode() == 202) {
            result.complete = false;
        } else if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            result.complete = true;
            result.itemId = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('id');
        } else {
            throw graphError('Upload to OneDrive failed', res);
        }
        return result;
    }

    // Creates the preview link for the uploaded file and stores it as a Sub Document under the Document.
    @AuraEnabled
    public static UploadResult saveSubDocument(Id documentId, String itemId, String fileName) {
        Document__c doc = getFolderDocument(documentId);
        String encodedItemId = EncodingUtil.urlEncode(itemId, 'UTF-8');

        HttpResponse itemRes = new Http().send(graphRequest('GET', GRAPH_ITEMS + encodedItemId + '?$select=id,parentReference'));
        if (itemRes.getStatusCode() != 200) {
            throw graphError('Could not find the uploaded file in OneDrive', itemRes);
        }
        Map<String, Object> parentRef = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(itemRes.getBody())).get('parentReference');
        if (parentRef == null || !doc.Document_Id__c.equals((String) parentRef.get('id'))) {
            throw userError('The uploaded file is not in the selected folder.');
        }

        // "Anyone with the link" view link; falls back to an organization link if the tenant blocks public links
        UploadResult result = new UploadResult();
        result.isPublic = true;
        HttpResponse linkRes = createViewLink(encodedItemId, 'anonymous');
        if (linkRes.getStatusCode() < 200 || linkRes.getStatusCode() >= 300) {
            result.isPublic = false;
            linkRes = createViewLink(encodedItemId, 'organization');
            if (linkRes.getStatusCode() < 200 || linkRes.getStatusCode() >= 300) {
                throw graphError('Could not create a preview link', linkRes);
            }
        }
        Map<String, Object> link = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(linkRes.getBody())).get('link');
        result.fileUrl = (String) link.get('webUrl');

        Sub_Document__c subDoc = new Sub_Document__c(
            Name = cleanFileName(fileName).left(80),
            Document__c = doc.Id,
            Project__c = doc.Project__c,
            File_URL__c = result.fileUrl
        );
        Database.insert(subDoc, AccessLevel.SYSTEM_MODE);
        result.subDocumentId = subDoc.Id;
        return result;
    }

    private static HttpResponse createViewLink(String encodedItemId, String scope) {
        HttpRequest req = graphRequest('POST', GRAPH_ITEMS + encodedItemId + '/createLink');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'type' => 'view', 'scope' => scope }));
        return new Http().send(req);
    }

    private static Document__c getFolderDocument(Id documentId) {
        List<Document__c> docs = [
            SELECT Id, Project__c, Document_Id__c
            FROM Document__c
            WHERE Id = :documentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (docs.isEmpty() || String.isBlank(docs[0].Document_Id__c)) {
            throw userError('This folder is not ready in OneDrive yet. Please try again in a minute.');
        }
        return docs[0];
    }

    private static String cleanFileName(String fileName) {
        String name = String.isBlank(fileName) ? '' : fileName.trim();
        if (!ALLOWED_EXTENSIONS.contains(name.substringAfterLast('.').toLowerCase())) {
            throw userError('Only PDF, JPG, JPEG, PNG and MP4 files can be uploaded.');
        }
        // Characters OneDrive does not accept in file names
        return name.replaceAll('[\\\\/:*?"<>|#%]', '_');
    }

    private static String encodePathSegment(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
    }

    private static Boolean isOneDriveUploadUrl(String url) {
        if (String.isBlank(url) || !url.startsWith('https://')) {
            return false;
        }
        String host = url.removeStart('https://').substringBefore('/').toLowerCase();
        return host.endsWith('.sharepoint.com');
    }

    private static HttpRequest graphRequest(String method, String endpoint) {
        if (accessToken == null) {
            accessToken = new OneDriveService().getAccessToken();
        }
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(endpoint);
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(60000);
        return req;
    }

    private static AuraHandledException graphError(String message, HttpResponse res) {
        String code = '';
        try {
            Map<String, Object> err = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('error');
            code = err != null ? ': ' + err.get('code') : '';
        } catch (Exception e) {
            code = '';
        }
        return userError(message + ' (HTTP ' + res.getStatusCode() + code + ')');
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}