public with sharing class SharePointDocumentManagerController {

    // Folders and files live in the client's SharePoint document library; SharePointService gives every address, the
    // sign-in and the host that upload sessions and links are on (CreateSharePointFoldersQueueable uses the same library)
    private static final Set<String> ALLOWED_EXTENSIONS = new Set<String>{ 'pdf', 'jpg', 'jpeg', 'png', 'mp4' };
    // A Sub Document name holds 80 characters and SharePoint may add " 1" on a name conflict, so longer names are
    // shortened before upload; the name in SharePoint and in Salesforce then always match
    private static final Integer MAX_FILE_NAME = 70;
    // uploadBase64 sends 3,932,160 bytes per request: 12 x 320 KiB (Graph's unit for upload ranges) and a multiple of
    // 3, so every slice of the base64 text decodes on its own; one request stays well inside Apex's callout size limit
    private static final Integer BASE64_CHUNK_LENGTH = 5242880;

    public class DocumentFolder {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean hasFolder;
        @AuraEnabled public List<FileItem> files = new List<FileItem>();
        // Folders inside this one, for example each configuration's folder inside "Project Configurations"
        @AuraEnabled public List<DocumentFolder> folders = new List<DocumentFolder>();
    }

    public class FileItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String url;
        @AuraEnabled public Datetime uploadedOn;
        // Project Configurations that show this file as their document
        @AuraEnabled public List<String> linkedConfigurations = new List<String>();
        // Whether the running user may delete uploaded files
        @AuraEnabled public Boolean canDelete = false;
    }

    public class ChunkResult {
        @AuraEnabled public Boolean complete;
        @AuraEnabled public String itemId;
    }

    public class UploadResult {
        @AuraEnabled public Id subDocumentId;
        @AuraEnabled public String fileUrl;
        @AuraEnabled public Boolean isPublic;
        // The file's name in SharePoint (conflictBehavior=rename may have added a number)
        @AuraEnabled public String storedName;
    }

    // Lists the Document folders of any record with their sub-folders (one level down) and the files
    // (Sub Documents) already uploaded to each.
    @AuraEnabled
    public static List<DocumentFolder> getDocuments(Id recordId, String relationshipField) {
        String lookupField = resolveLookupField(recordId.getSObjectType(), relationshipField);
        List<Document__c> docs = Database.queryWithBinds(
            'SELECT Id, Name, Status__c, Document_Id__c FROM Document__c WHERE ' + lookupField + ' = :recordId ORDER BY CreatedDate, Name',
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.SYSTEM_MODE
        );

        Map<Id, DocumentFolder> foldersById = new Map<Id, DocumentFolder>();
        List<DocumentFolder> folders = new List<DocumentFolder>();
        for (Document__c doc : docs) {
            DocumentFolder folder = toFolder(doc);
            folders.add(folder);
            foldersById.put(doc.Id, folder);
        }

        // A sub-folder is shown inside its parent only, sorted by name so configuration folders follow their numbers
        Set<Id> nested = new Set<Id>();
        if (!foldersById.isEmpty()) {
            Set<Id> parentIds = new Set<Id>(foldersById.keySet());
            for (Document__c child : [
                SELECT Id, Name, Status__c, Document_Id__c, Parent_Document__c
                FROM Document__c
                WHERE Parent_Document__c IN :parentIds
                WITH SYSTEM_MODE
                ORDER BY Name
            ]) {
                DocumentFolder sub = foldersById.containsKey(child.Id) ? foldersById.get(child.Id) : toFolder(child);
                foldersById.get(child.Parent_Document__c).folders.add(sub);
                foldersById.put(child.Id, sub);
                nested.add(child.Id);
            }
        }
        List<DocumentFolder> topLevel = new List<DocumentFolder>();
        for (DocumentFolder folder : folders) {
            if (!nested.contains(folder.id)) {
                topLevel.add(folder);
            }
        }

        List<FileItem> allFiles = new List<FileItem>();
        for (Sub_Document__c sub : [
            SELECT Id, Name, File_URL__c, CreatedDate, Document__c, (SELECT Name FROM Project_Configurations__r ORDER BY Name)
            FROM Sub_Document__c
            WHERE Document__c IN :foldersById.keySet()
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            FileItem file = new FileItem();
            file.id = sub.Id;
            file.name = sub.Name;
            file.url = sub.File_URL__c;
            file.uploadedOn = sub.CreatedDate;
            for (Project_Configuration__c config : sub.Project_Configurations__r) {
                file.linkedConfigurations.add(config.Name);
            }
            foldersById.get(sub.Document__c).files.add(file);
            allFiles.add(file);
        }
        // Delete is offered only for files this user may really delete (object permission and record access)
        if (Schema.SObjectType.Sub_Document__c.isDeletable() && !allFiles.isEmpty()) {
            List<Id> fileIds = new List<Id>();
            for (FileItem file : allFiles) {
                fileIds.add(file.id);
            }
            Set<Id> deletable = deletableRecords(fileIds);
            for (FileItem file : allFiles) {
                file.canDelete = deletable.contains(file.id);
            }
        }
        return topLevel;
    }

    private static DocumentFolder toFolder(Document__c doc) {
        DocumentFolder folder = new DocumentFolder();
        folder.id = doc.Id;
        folder.name = doc.Name;
        folder.status = doc.Status__c;
        folder.hasFolder = String.isNotBlank(doc.Document_Id__c);
        return folder;
    }

    // Largest file the upload screens accept, in bytes (Max Upload Size in the SharePoint setting)
    @AuraEnabled(cacheable=true)
    public static Long getMaxUploadBytes() {
        return SharePointService.maxUploadBytes();
    }

    // Starts a SharePoint upload session inside the Document's folder; the file itself is sent with uploadChunk.
    @AuraEnabled
    public static String createUploadSession(Id documentId, String fileName) {
        return startUploadSession(getFolderDocument(documentId).Document_Id__c, fileName);
    }

    // Sends one byte range of the file. SharePoint answers 202 until the last range, then 200/201 with the new item.
    @AuraEnabled
    public static ChunkResult uploadChunk(String uploadUrl, String base64Chunk, Long startByte, Long endByte, Long totalSize) {
        return putRange(uploadUrl, EncodingUtil.base64Decode(base64Chunk), startByte, endByte, totalSize);
    }

    // ---------- by SharePoint folder id, for features that make their own folders (Partner Portal registration) ----------

    // Creates a folder inside another, or at the top of the library when parentFolderId is blank, and returns its id.
    // SharePoint renames it when the name is taken; characters it refuses become "_".
    public static String createFolder(String parentFolderId, String name) {
        String endpoint = String.isBlank(parentFolderId)
            ? SharePointService.rootChildrenUrl()
            : SharePointService.itemsUrl() + parentFolderId + '/children';
        HttpRequest req = SharePointService.request('POST', endpoint);
        req.setBody(JSON.serialize(new Map<String, Object>{
            'name' => folderName(name),
            'folder' => new Map<String, Object>(),
            '@microsoft.graph.conflictBehavior' => 'rename'
        }));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw graphError('Could not create the folder in SharePoint', res);
        }
        return (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('id');
    }

    // Starts an upload session for a file inside a folder and returns its upload URL
    public static String startUploadSession(String folderId, String fileName) {
        return startUploadSession(folderId, fileName, true);
    }

    // The same, optionally without this component's own list of file types, for callers that apply their own rules
    // (the Partner Portal registration follows its Allowed File Types setting)
    public static String startUploadSession(String folderId, String fileName, Boolean checkFileType) {
        String cleanName = cleanFileName(fileName, checkFileType);
        HttpRequest req = SharePointService.request('POST',
            SharePointService.itemsUrl() + folderId + ':/' + encodePathSegment(cleanName) + ':/createUploadSession');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'item' => new Map<String, Object>{ '@microsoft.graph.conflictBehavior' => 'rename' }
        }));
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw graphError('Could not start the upload in SharePoint', res);
        }
        return (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('uploadUrl');
    }

    // Uploads a whole file given as base64 into a folder, one slice per request, and returns the new item's id. Only one
    // slice is decoded at a time, so a 10 MB file never sits in memory twice.
    public static String uploadBase64(String folderId, String fileName, String base64Data, Boolean checkFileType) {
        String data = base64Data == null ? '' : base64Data;
        Long total = (Long) (data.length() / 4) * 3 - (data.endsWith('==') ? 2 : (data.endsWith('=') ? 1 : 0));
        if (total <= 0) {
            throw userError(fileName + ' could not be read. Please choose it again.');
        }
        String uploadUrl = startUploadSession(folderId, fileName, checkFileType);
        String itemId;
        for (Integer offset = 0; offset < data.length(); offset += BASE64_CHUNK_LENGTH) {
            Blob bytes = EncodingUtil.base64Decode(data.substring(offset, Math.min(offset + BASE64_CHUNK_LENGTH, data.length())));
            Long startByte = (Long) (offset / 4) * 3;
            ChunkResult result = putRange(uploadUrl, bytes, startByte, startByte + bytes.size(), total);
            if (result.complete) {
                itemId = result.itemId;
            }
        }
        if (itemId == null) {
            throw userError('SharePoint did not confirm the upload of ' + fileName + '.');
        }
        return itemId;
    }

    // Checks that an uploaded item really is in the folder and gives it a public view link (an organization link when
    // the tenant refuses public ones); no record is saved
    public static UploadResult linkFile(String folderId, String itemId) {
        String encodedItemId = EncodingUtil.urlEncode(itemId, 'UTF-8');
        HttpResponse itemRes = new Http().send(SharePointService.request('GET',
            SharePointService.itemsUrl() + encodedItemId + '?$select=id,name,parentReference'));
        if (itemRes.getStatusCode() != 200) {
            throw graphError('Could not find the uploaded file in SharePoint', itemRes);
        }
        Map<String, Object> item = (Map<String, Object>) JSON.deserializeUntyped(itemRes.getBody());
        Map<String, Object> parentRef = (Map<String, Object>) item.get('parentReference');
        if (parentRef == null || String.isBlank(folderId) || !folderId.equals((String) parentRef.get('id'))) {
            throw userError('The uploaded file is not in the selected folder.');
        }

        // "Anyone with the link" view link. Only a policy refusal (400/403) falls back to an organization link;
        // throttling or outages fail the file so it can be retried and still get a public link.
        HttpResponse linkRes = createViewLink(encodedItemId, 'anonymous');
        if (linkRes.getStatusCode() == 400 || linkRes.getStatusCode() == 403) {
            linkRes = createViewLink(encodedItemId, 'organization');
        }
        if (linkRes.getStatusCode() < 200 || linkRes.getStatusCode() >= 300) {
            throw graphError('Could not create a preview link', linkRes);
        }
        Map<String, Object> link = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(linkRes.getBody())).get('link');
        UploadResult result = new UploadResult();
        result.fileUrl = (String) link.get('webUrl');
        result.isPublic = 'anonymous'.equals((String) link.get('scope'));
        result.storedName = (String) item.get('name');
        return result;
    }

    // Sends one byte range to an upload session (for callers that keep the session URL themselves)
    public static ChunkResult uploadBytes(String uploadUrl, Blob bytes, Long startByte, Long endByte, Long totalSize) {
        return putRange(uploadUrl, bytes, startByte, endByte, totalSize);
    }

    // How many files (not folders) a folder holds in SharePoint, up to 200
    public static Integer countFiles(String folderId) {
        HttpResponse res = new Http().send(SharePointService.request('GET',
            SharePointService.itemsUrl() + folderId + '/children?$select=id,file&$top=200'));
        if (res.getStatusCode() != 200) {
            throw graphError('Could not read the folder in SharePoint', res);
        }
        Integer files = 0;
        for (Object entry : (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('value')) {
            if (((Map<String, Object>) entry).get('file') != null) {
                files++;
            }
        }
        return files;
    }

    // Upload-session URLs are pre-signed by SharePoint, so the range goes straight to them, not through the Named Credential
    private static ChunkResult putRange(String uploadUrl, Blob bytes, Long startByte, Long endByte, Long totalSize) {
        if (!isDriveUrl(uploadUrl)) {
            throw userError('Invalid upload session.');
        }
        HttpRequest req = new HttpRequest();
        req.setMethod('PUT');
        req.setEndpoint(uploadUrl);
        req.setHeader('Content-Range', 'bytes ' + startByte + '-' + (endByte - 1) + '/' + totalSize);
        req.setBodyAsBlob(bytes);
        req.setTimeout(120000);
        HttpResponse res = new Http().send(req);

        ChunkResult result = new ChunkResult();
        if (res.getStatusCode() == 202) {
            result.complete = false;
        } else if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            result.complete = true;
            result.itemId = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('id');
        } else {
            throw graphError('Upload to SharePoint failed', res);
        }
        return result;
    }

    // Creates the public preview link for the uploaded file and stores it as a Sub Document under the Document.
    @AuraEnabled
    public static UploadResult saveSubDocument(Id documentId, String itemId, String fileName) {
        Document__c doc = getFolderDocument(documentId);
        UploadResult result = linkFile(doc.Document_Id__c, itemId);

        // Name as SharePoint stored it (conflictBehavior=rename may have added a number)
        String storedName = result.storedName;
        Sub_Document__c subDoc = new Sub_Document__c(
            Name = (String.isNotBlank(storedName) ? storedName : cleanFileName(fileName)).left(80),
            Document__c = doc.Id,
            File_URL__c = result.fileUrl,
            Public_Link__c = result.isPublic
        );
        Database.insert(subDoc, AccessLevel.SYSTEM_MODE);
        result.subDocumentId = subDoc.Id;
        return result;
    }

    // Deletes one uploaded file: the SharePoint file goes to the site's recycle bin and its Sub Document is removed
    // (a configuration that showed it then has no document). Folders are never deleted.
    @AuraEnabled
    public static void deleteFile(Id subDocumentId) {
        if (subDocumentId == null || subDocumentId.getSObjectType() != Sub_Document__c.SObjectType) {
            throw userError('Choose a file to delete.');
        }
        if (!Schema.SObjectType.Sub_Document__c.isDeletable()) {
            throw userError('You do not have permission to delete this file.');
        }
        List<Sub_Document__c> subs = [
            SELECT Id, Name, File_URL__c, Document__r.Document_Id__c
            FROM Sub_Document__c
            WHERE Id = :subDocumentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (subs.isEmpty()) {
            throw userError('This file was already deleted. Refresh the list.');
        }
        if (!deletableRecords(new List<Id>{ subDocumentId }).contains(subDocumentId)) {
            throw userError('You do not have permission to delete this file.');
        }

        // Callouts come before the record is deleted (no callouts are allowed after DML in a transaction)
        String itemId = findFileInFolder(subs[0]);
        if (itemId != null) {
            HttpResponse res = new Http().send(SharePointService.request('DELETE',
                SharePointService.itemsUrl() + EncodingUtil.urlEncode(itemId, 'UTF-8')));
            if (res.getStatusCode() != 204 && res.getStatusCode() != 404) {
                throw graphError('SharePoint could not delete the file', res);
            }
        }
        // Access was checked above; the file is gone from SharePoint (or was already)
        Database.delete(subs[0], AccessLevel.SYSTEM_MODE);
    }

    // The file's SharePoint item inside its own folder. The share link identifies that exact file, even after a rename or
    // when another file now has the same name; only a record without a link is looked up by name. Null when SharePoint no
    // longer has the file, or when the link is not a SharePoint file at all (then only the record is removed). Anything
    // that is not a file inside that folder is refused, so a folder is never deleted.
    private static String findFileInFolder(Sub_Document__c sub) {
        String folderId = sub.Document__r == null ? null : sub.Document__r.Document_Id__c;
        if (String.isBlank(folderId)) {
            return null;
        }
        String fields = '?$select=id,parentReference,file,folder';
        HttpRequest lookup;
        if (String.isBlank(sub.File_URL__c)) {
            lookup = SharePointService.request('GET', SharePointService.itemsUrl() + folderId + ':/' + encodePathSegment(sub.Name) + fields);
        } else if (isDriveUrl(sub.File_URL__c)) {
            lookup = SharePointService.request('GET', SharePointService.sharesUrl() + shareId(sub.File_URL__c) + '/driveItem' + fields);
        } else {
            return null;
        }
        HttpResponse res = new Http().send(lookup);
        if (res.getStatusCode() == 404) {
            return null;
        }
        if (res.getStatusCode() != 200) {
            throw graphError('Could not find the file in SharePoint', res);
        }
        Map<String, Object> item = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> parentRef = (Map<String, Object>) item.get('parentReference');
        if (item.get('folder') != null || item.get('file') == null) {
            throw userError('Only files can be deleted, not folders.');
        }
        if (parentRef == null || !folderId.equals((String) parentRef.get('id'))) {
            throw userError('This file is no longer in its folder in SharePoint, so nothing was deleted.');
        }
        return (String) item.get('id');
    }

    // Graph addresses a share link as "u!" + unpadded base64url of the link (the portal resolves files with it too)
    public static String shareId(String url) {
        String encoded = EncodingUtil.base64Encode(Blob.valueOf(url)).replace('+', '-').replace('/', '_');
        return 'u!' + encoded.removeEnd('=').removeEnd('=');
    }

    // Records the running user can delete (object permission and sharing); UserRecordAccess takes 200 ids per query
    private static Set<Id> deletableRecords(List<Id> recordIds) {
        Set<Id> deletable = new Set<Id>();
        for (Integer start = 0; start < recordIds.size(); start += 200) {
            List<Id> chunk = new List<Id>();
            for (Integer i = start; i < Math.min(start + 200, recordIds.size()); i++) {
                chunk.add(recordIds[i]);
            }
            for (UserRecordAccess access : [
                SELECT RecordId, HasDeleteAccess
                FROM UserRecordAccess
                WHERE UserId = :UserInfo.getUserId() AND RecordId IN :chunk
            ]) {
                if (access.HasDeleteAccess) {
                    deletable.add(access.RecordId);
                }
            }
        }
        return deletable;
    }

    // Finds the lookup on Document__c that points at the record's object, so the component works on any object.
    @TestVisible
    private static String resolveLookupField(Schema.SObjectType recordType, String preferredField) {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Document__c.fields.getMap();
        String objectLabel = recordType.getDescribe().getLabel();

        if (String.isNotBlank(preferredField)) {
            Schema.SObjectField field = fields.get(preferredField.trim().toLowerCase());
            if (field != null && field.getDescribe().getReferenceTo().contains(recordType)) {
                return field.getDescribe().getName();
            }
            throw userError('"' + preferredField + '" is not a Document lookup to ' + objectLabel + '.');
        }

        String firstMatch;
        String objectName = recordType.getDescribe().getName();
        for (Schema.SObjectField field : fields.values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.getType() != Schema.DisplayType.REFERENCE || !describe.isCustom()
                    || !describe.getReferenceTo().contains(recordType)) {
                continue;
            }
            // Prefer the lookup named after the object (Project__c on Project__c)
            if (describe.getName().equalsIgnoreCase(objectName) || describe.getName().equalsIgnoreCase(objectName + '__c')) {
                return describe.getName();
            }
            if (firstMatch == null) {
                firstMatch = describe.getName();
            }
        }
        if (firstMatch == null) {
            throw userError('Documents are not linked to ' + objectLabel + ' records. Add a lookup to ' + objectLabel + ' on the Document object.');
        }
        return firstMatch;
    }

    private static HttpResponse createViewLink(String encodedItemId, String scope) {
        HttpRequest req = SharePointService.request('POST', SharePointService.itemsUrl() + encodedItemId + '/createLink');
        req.setBody(JSON.serialize(new Map<String, Object>{ 'type' => 'view', 'scope' => scope }));
        return new Http().send(req);
    }

    private static Document__c getFolderDocument(Id documentId) {
        List<Document__c> docs = [
            SELECT Id, Document_Id__c
            FROM Document__c
            WHERE Id = :documentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (docs.isEmpty() || String.isBlank(docs[0].Document_Id__c)) {
            throw userError('This folder is not ready in SharePoint yet. Please refresh in a minute.');
        }
        return docs[0];
    }

    @TestVisible
    private static String cleanFileName(String fileName) {
        return cleanFileName(fileName, true);
    }

    private static String cleanFileName(String fileName, Boolean checkFileType) {
        String name = String.isBlank(fileName) ? '' : fileName.trim();
        String extension = name.substringAfterLast('.');
        if (checkFileType != false && !ALLOWED_EXTENSIONS.contains(extension.toLowerCase())) {
            throw userError('Only PDF, JPG, JPEG, PNG and MP4 files can be uploaded.');
        }
        // Characters SharePoint does not accept in file names
        name = name.replaceAll('[\\\\/:*?"<>|#%]', '_');
        if (name.length() > MAX_FILE_NAME) {
            name = String.isBlank(extension) || !name.contains('.')
                ? name.left(MAX_FILE_NAME).trim()
                : name.substringBeforeLast('.').left(MAX_FILE_NAME - extension.length() - 1).trim() + '.' + extension;
        }
        return name;
    }

    // A folder name SharePoint accepts: no \\ / : * ? " < > | # %, no leading or trailing spaces or dots, at most 200
    // characters (CreateSharePointFoldersQueueable names its folders with it too)
    public static String folderName(String name) {
        String clean = (name == null ? '' : name).replaceAll('[\\\\/:*?"<>|#%\\p{Cntrl}]', '_').trim();
        clean = clean.replaceAll('^[. ]+|[. ]+$', '').left(200).trim();
        return String.isBlank(clean) ? 'Untitled' : clean;
    }

    private static String encodePathSegment(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
    }

    // True for an https link on the SharePoint host (upload sessions and share links)
    public static Boolean isDriveUrl(String url) {
        if (String.isBlank(url) || !url.startsWith('https://')) {
            return false;
        }
        // Authority ends at the first '/', '?' or '#'; it must be exactly the SharePoint host (no user info or port tricks)
        String authority = url.removeStart('https://');
        Integer cut = authority.length();
        for (String stop : new List<String>{ '/', '?', '#' }) {
            Integer idx = authority.indexOf(stop);
            if (idx >= 0 && idx < cut) {
                cut = idx;
            }
        }
        String host = SharePointService.host();
        return String.isNotBlank(host) && authority.left(cut).equalsIgnoreCase(host);
    }

    // The file behind a Sub Document's link: its name, size and a short-lived download URL that needs no sign-in (for
    // pages that let someone without SharePoint access save the file, such as the Partner Portal's My Contract)
    public class DriveFile {
        public String name;
        public Long size;
        public String downloadUrl;
    }

    public static DriveFile fileBehindLink(String fileUrl) {
        HttpResponse res = new Http().send(SharePointService.request('GET', SharePointService.sharesUrl() + shareId(fileUrl) + '/driveItem'));
        if (res.getStatusCode() != 200) {
            throw graphError('Could not find the file in SharePoint', res);
        }
        Map<String, Object> item = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        DriveFile file = new DriveFile();
        file.name = (String) item.get('name');
        file.size = item.get('size') == null ? null : Long.valueOf(String.valueOf(item.get('size')));
        file.downloadUrl = (String) item.get('@microsoft.graph.downloadUrl');
        return file;
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