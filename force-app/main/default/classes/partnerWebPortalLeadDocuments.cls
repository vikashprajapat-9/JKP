// The Documents popup of the Partner Portal's Leads page (the Lead Nurturing chart: "Document collection by agent"):
// the channel partner collects the customer's documents by customer type, Individual or Company, and uploads them
// against the lead. The documents to collect are the categories of the Document Master the Partner Portal Setting
// names for the type (Lead Individual / Company Document Master). Files go to SharePoint: a folder per lead inside the
// partner account's folder (at the top of the library when the account has none), with a sub-folder per category (a
// Document record of the lead); each file is a Sub Document with its view link. JKP sees them on the lead (Documents
// panel), and after the conversion on the account and the opportunity (PartnerLeadHandover).
// Only the partner's own leads take documents (an executive's own; not booked, lost or waiting for approval), also
// after the JKP CP team took the lead over. Partners cannot see internal records, so this runs without sharing in
// system mode, and every lead is checked against the logged-in partner (PartnerPortalAccess). The page never gets
// SharePoint's upload URL: it gets a signed, encrypted handle, and its chunks go through Apex.
public without sharing class partnerWebPortalLeadDocuments {

    public class DocumentFile {
        @AuraEnabled public String name;
        @AuraEnabled public String url;
        @AuraEnabled public String uploadedOn;
    }

    // A document to collect (a category), with the files already uploaded
    public class Category {
        @AuraEnabled public String name;
        @AuraEnabled public Id documentId;
        @AuraEnabled public List<DocumentFile> files = new List<DocumentFile>();
    }

    public class LeadDocuments {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String stage;
        @AuraEnabled public String projectName;
        @AuraEnabled public String customerType;
        @AuraEnabled public List<Map<String, String>> typeOptions = new List<Map<String, String>>();
        // Files are uploaded, so the customer type can no longer change
        @AuraEnabled public Boolean typeLocked = false;
        @AuraEnabled public Boolean canUpload = false;
        @AuraEnabled public String readOnlyReason;
        // Why there is nothing to upload yet (no type chosen, no document list set up), or null
        @AuraEnabled public String notice;
        @AuraEnabled public String guidance;
        @AuraEnabled public Decimal maxSizeMb;
        @AuraEnabled public List<Category> categories = new List<Category>();
    }

    // What a handle carries: SharePoint's upload URL, the Document (category folder), the lead, the size and the name
    @TestVisible
    private class UploadSession {
        @TestVisible String u;
        @TestVisible Id d;
        @TestVisible Id l;
        @TestVisible Long s;
        @TestVisible String n;
    }

    private static final Set<String> ALLOWED_TYPES = new Set<String>{ 'pdf', 'jpg', 'jpeg', 'png' };
    // The start of each file type, base64 (a renamed file of another type is refused)
    private static final Map<String, String> FILE_SIGNATURES = new Map<String, String>{
        'pdf' => 'JVBER', 'jpg' => '/9j/', 'jpeg' => '/9j/', 'png' => 'iVBORw0KGgo'
    };
    private static final Integer MAX_CHUNK_BYTES = 4 * 1024 * 1024;
    private static final Decimal DEFAULT_MAX_MB = 10;
    private static final String INDIVIDUAL = 'Individual';
    private static final String COMPANY = 'Company';

    // What the popup tells the partner: its notes, why a lead is read-only, and the refusals
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_HINT = 'Upload the customer\'s documents for John Keells Properties: PDF, JPG or PNG, up to {0} MB each.';
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_CHOOSE_TYPE = 'Choose whether the customer is an Individual or a Company.';
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_NO_CATEGORIES = 'No document list is set up for {0} customers yet. Please contact the JKP CP team.';
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_TYPE_LOCKED = 'Documents are already uploaded for this {0} customer, so the customer type cannot be changed.';
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_UPLOAD_EXPIRED = 'This upload is no longer valid. Please choose the file again.';
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_WRONG_FILE = '{0} is not a valid {1} file.';
    private static final String PARTNER_PORTAL_NO_ACCESS = 'Your Partner Portal access is not active. Please contact the JKP CP team.';
    @TestVisible
    private static final String PARTNER_LEAD_READ_ONLY_TEAM = 'Your executive\'s lead: only they can update it.';
    private static final String PARTNER_LEAD_READ_ONLY_BOOKED = 'Booked: this lead has been converted.';
    private static final String PARTNER_LEAD_READ_ONLY_WAITING = 'Waiting for approval by the Direct Sales Manager and JKP CP Manager.';
    private static final String PARTNER_LEAD_READ_ONLY_LOST = 'Closed: another channel partner won this customer.';
    private static final String PARTNER_LEAD_EDIT_NOT_FOUND = 'This lead is not in your Leads list.';
    @TestVisible
    private static final String PARTNER_LEAD_DOCS_TOO_LARGE = '{0} is larger than {1} MB.';

    // Tests set their own
    @TestVisible
    private static Partner_Portal_Setting__mdt setting = Partner_Portal_Setting__mdt.getInstance('Default');

    // =====================================================================================================
    // READ AND CHOOSE THE CUSTOMER TYPE
    // =====================================================================================================

    @AuraEnabled
    public static LeadDocuments getLeadDocuments(Id leadId) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        Lead record = leadOf(leadId, access);
        LeadDocuments result = new LeadDocuments();
        result.leadId = record.Id;
        result.leadName = record.Name;
        result.stage = record.Status;
        result.projectName = record.Project__r == null ? null : record.Project__r.Name;
        result.customerType = record.Customer_Type__c;
        result.readOnlyReason = uploadReason(record, access);
        result.canUpload = result.readOnlyReason == null;
        result.maxSizeMb = maxSizeMb();
        // String.format reads an apostrophe as quoting, so it is doubled to keep "customer's" and fill {0}
        result.guidance = String.format(PARTNER_LEAD_DOCS_HINT.replace('\'', '\'\''), new List<Object>{ String.valueOf(result.maxSizeMb.intValue()) });
        for (PicklistEntry entry : Lead.Customer_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                result.typeOptions.add(new Map<String, String>{ 'label' => entry.getLabel(), 'value' => entry.getValue() });
            }
        }

        Map<String, Document__c> documents = documentsOf(record.Id);
        Map<Id, List<Sub_Document__c>> filesByDocument = filesOf(documents.values());
        result.typeLocked = !filesByDocument.isEmpty();
        List<String> names = String.isBlank(record.Customer_Type__c) ? new List<String>() : categoriesFor(record.Customer_Type__c);
        // Documents already collected stay listed even if the list changed since
        for (String name : documents.keySet()) {
            if (!containsIgnoreCase(names, documents.get(name).Name) && filesByDocument.containsKey(documents.get(name).Id)) {
                names.add(documents.get(name).Name);
            }
        }
        if (String.isBlank(record.Customer_Type__c)) {
            result.notice = PARTNER_LEAD_DOCS_CHOOSE_TYPE;
        } else if (names.isEmpty()) {
            result.notice = String.format(PARTNER_LEAD_DOCS_NO_CATEGORIES, new List<Object>{ record.Customer_Type__c });
        }
        for (String name : names) {
            Category category = new Category();
            category.name = name;
            Document__c document = documents.get(name.toLowerCase());
            if (document != null) {
                category.documentId = document.Id;
                for (Sub_Document__c file : filesByDocument.containsKey(document.Id) ? filesByDocument.get(document.Id) : new List<Sub_Document__c>()) {
                    DocumentFile item = new DocumentFile();
                    item.name = file.Name;
                    item.url = file.File_URL__c;
                    item.uploadedOn = file.CreatedDate == null ? '' : file.CreatedDate.format('d MMM yyyy');
                    category.files.add(item);
                }
            }
            result.categories.add(category);
        }
        return result;
    }

    // The customer is an Individual or a Company; it decides the documents to collect. Fixed once files are uploaded.
    @AuraEnabled
    public static LeadDocuments setCustomerType(Id leadId, String customerType) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        Lead record = leadOf(leadId, access);
        String reason = uploadReason(record, access);
        if (reason != null) {
            throw userError(reason);
        }
        String chosen = null;
        for (PicklistEntry entry : Lead.Customer_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == customerType) {
                chosen = entry.getValue();
            }
        }
        if (chosen == null) {
            throw userError(PARTNER_LEAD_DOCS_CHOOSE_TYPE);
        }
        if (chosen != record.Customer_Type__c) {
            if (!filesOf(documentsOf(record.Id).values()).isEmpty()) {
                throw userError(String.format(PARTNER_LEAD_DOCS_TYPE_LOCKED, new List<Object>{ record.Customer_Type__c }));
            }
            try {
                Database.update(new Lead(Id = record.Id, Customer_Type__c = chosen), AccessLevel.SYSTEM_MODE);
            } catch (DmlException e) {
                throw userError(e.getDmlMessage(0));
            }
        }
        return getLeadDocuments(leadId);
    }

    // =====================================================================================================
    // UPLOAD: start (folders and the upload session), chunks, finish (link and Sub Document)
    // =====================================================================================================

    // Starts the upload of one file of a document to collect and returns its handle. The lead's folder and the
    // document's folder are made in SharePoint first, then saved (callouts cannot follow DML).
    @AuraEnabled
    public static String startUpload(Id leadId, String category, String fileName, Long size) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        Lead record = leadOf(leadId, access);
        String reason = uploadReason(record, access);
        if (reason != null) {
            throw userError(reason);
        }
        if (String.isBlank(record.Customer_Type__c)) {
            throw userError(PARTNER_LEAD_DOCS_CHOOSE_TYPE);
        }
        String categoryName = null;
        for (String name : categoriesFor(record.Customer_Type__c)) {
            if (String.isNotBlank(category) && name.equalsIgnoreCase(category.trim())) {
                categoryName = name;
            }
        }
        if (categoryName == null) {
            throw userError(String.format(PARTNER_LEAD_DOCS_NO_CATEGORIES, new List<Object>{ record.Customer_Type__c }));
        }
        String name = String.isBlank(fileName) ? '' : fileName.trim();
        String problem = fileProblem(name, size);
        if (problem != null) {
            throw userError(problem);
        }

        Document__c document = documentsOf(record.Id).get(categoryName.toLowerCase());
        String leadFolderId = record.Document_Id__c;
        Boolean newLeadFolder = false;
        String uploadUrl;
        try {
            if (document == null) {
                if (String.isBlank(leadFolderId)) {
                    String parentFolder = record.Channel_Partner__r == null ? null : record.Channel_Partner__r.Document_Id__c;
                    leadFolderId = SharePointDocumentManagerController.createFolder(parentFolder, 'Lead - ' + record.Name);
                    newLeadFolder = true;
                }
                document = new Document__c(
                    Name = categoryName.left(80),
                    Lead__c = record.Id,
                    Document_Id__c = SharePointDocumentManagerController.createFolder(leadFolderId, categoryName),
                    Status__c = 'Pending',
                    OwnerId = record.Channel_Partner__r == null ? UserInfo.getUserId() : record.Channel_Partner__r.OwnerId
                );
            }
            uploadUrl = SharePointDocumentManagerController.startUploadSession(document.Document_Id__c, name, true);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw userError(e.getMessage());
        }
        try {
            if (newLeadFolder) {
                Database.update(new Lead(Id = record.Id, Document_Id__c = leadFolderId), AccessLevel.SYSTEM_MODE);
            }
            if (document.Id == null) {
                Database.insert(document, AccessLevel.SYSTEM_MODE);
            }
        } catch (DmlException e) {
            throw userError(e.getDmlMessage(0));
        }
        UploadSession session = new UploadSession();
        session.u = uploadUrl;
        session.d = document.Id;
        session.l = record.Id;
        session.s = size;
        session.n = name;
        return handleFor(session);
    }

    // Sends one chunk of a file that startUpload began: it must fit the size accepted at the start, and the first one
    // must look like the file type its name says
    @AuraEnabled
    public static SharePointDocumentManagerController.ChunkResult uploadChunk(Id leadId, String handle, String base64Chunk, Long startByte,
            Long endByte) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        Lead record = leadOf(leadId, access);
        String reason = uploadReason(record, access);
        if (reason != null) {
            throw userError(reason);
        }
        UploadSession session = sessionOf(handle, record.Id);
        Blob bytes;
        try {
            bytes = EncodingUtil.base64Decode(base64Chunk == null ? '' : base64Chunk);
        } catch (Exception e) {
            bytes = null;
        }
        if (bytes == null || startByte == null || endByte == null || startByte < 0 || endByte > session.s || bytes.size() == 0
                || bytes.size() > MAX_CHUNK_BYTES || bytes.size() != endByte - startByte) {
            throw userError(PARTNER_LEAD_DOCS_UPLOAD_EXPIRED);
        }
        String extension = extensionOf(session.n);
        String signature = FILE_SIGNATURES.get(extension);
        if (startByte == 0 && signature != null && !base64Chunk.startsWith(signature)) {
            throw userError(String.format(PARTNER_LEAD_DOCS_WRONG_FILE, new List<Object>{ session.n, extension.toUpperCase() }));
        }
        try {
            return SharePointDocumentManagerController.uploadBytes(session.u, bytes, startByte, endByte, session.s);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw userError(e.getMessage());
        }
    }

    // Finishes a file: checks SharePoint has it in the document's folder, gives it a view link and saves its Sub
    // Document (callouts first). Finishing the same file again changes nothing, so the page can retry safely.
    @AuraEnabled
    public static LeadDocuments finishUpload(Id leadId, String handle, String itemId) {
        PartnerPortalAccess access = PartnerPortalAccess.current();
        Lead record = leadOf(leadId, access);
        String reason = uploadReason(record, access);
        if (reason != null) {
            throw userError(reason);
        }
        UploadSession session = sessionOf(handle, record.Id);
        List<Document__c> documents = [
            SELECT Id, Document_Id__c, OwnerId, Status__c FROM Document__c WHERE Id = :session.d AND Lead__c = :record.Id WITH SYSTEM_MODE
        ];
        if (documents.isEmpty() || String.isBlank(itemId)) {
            throw userError(PARTNER_LEAD_DOCS_UPLOAD_EXPIRED);
        }
        Document__c document = documents[0];
        SharePointDocumentManagerController.UploadResult link;
        try {
            link = SharePointDocumentManagerController.linkFile(document.Document_Id__c, itemId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw userError(e.getMessage());
        }
        if ([SELECT COUNT() FROM Sub_Document__c WHERE Document__c = :document.Id AND File_URL__c = :link.fileUrl WITH SYSTEM_MODE] == 0) {
            Database.insert(new Sub_Document__c(
                Name = (String.isNotBlank(link.storedName) ? link.storedName : session.n).left(80),
                Document__c = document.Id,
                File_URL__c = link.fileUrl,
                Public_Link__c = link.isPublic == true,
                OwnerId = document.OwnerId
            ), AccessLevel.SYSTEM_MODE);
            if (document.Status__c != 'Uploaded') {
                Database.update(new Document__c(Id = document.Id, Status__c = 'Uploaded'), false, AccessLevel.SYSTEM_MODE);
            }
        }
        return getLeadDocuments(leadId);
    }

    // =====================================================================================================
    // WHO MAY UPLOAD
    // =====================================================================================================

    // Why the partner cannot upload documents for the lead, or null when they can: their own lead (an executive's own),
    // not booked, waiting for approval or lost to another partner; JKP may own it (after the hand-over)
    public static String uploadReason(Lead record, PartnerPortalAccess access) {
        if (access == null || access.accountId == null) {
            return PARTNER_PORTAL_NO_ACCESS;
        }
        if (record.Channel_Partner__c != access.accountId) {
            return PARTNER_LEAD_READ_ONLY_TEAM;
        }
        if (record.IsConverted) {
            return PARTNER_LEAD_READ_ONLY_BOOKED;
        }
        if (record.CP_Approval_Status__c == LeadLogicController.CP_APPROVAL_PENDING) {
            return PARTNER_LEAD_READ_ONLY_WAITING;
        }
        String lostStatus = setting == null ? null : setting.CP_Lead_Lost_Status__c;
        if (String.isNotBlank(lostStatus) && record.Status == lostStatus.trim()) {
            return PARTNER_LEAD_READ_ONLY_LOST;
        }
        return null;
    }

    // The lead, when it is one of the partner's team's leads
    private static Lead leadOf(Id leadId, PartnerPortalAccess access) {
        if (leadId == null || access.accountId == null) {
            throw userError(PARTNER_PORTAL_NO_ACCESS);
        }
        Map<String, Object> binds = new Map<String, Object>{ 'leadId' => leadId };
        List<Lead> leads = Database.queryWithBinds(
            'SELECT Id, Name, Status, OwnerId, IsConverted, CP_Approval_Status__c, Channel_Partner__c, Channel_Partner__r.Document_Id__c, '
                + 'Channel_Partner__r.OwnerId, Project__r.Name, Customer_Type__c, Document_Id__c FROM Lead WHERE Id = :leadId AND '
                + access.leads(binds) + ' LIMIT 1',
            binds, AccessLevel.SYSTEM_MODE);
        if (leads.isEmpty()) {
            throw userError(PARTNER_LEAD_EDIT_NOT_FOUND);
        }
        return leads[0];
    }

    // =====================================================================================================
    // HELPERS
    // =====================================================================================================

    // The documents to collect for a customer type: the categories of the type's Document Master, in the order they
    // were made
    @TestVisible
    private static List<String> categoriesFor(String customerType) {
        String masterName = null;
        if (setting != null) {
            masterName = customerType == INDIVIDUAL ? setting.Lead_Individual_Document_Master__c
                : (customerType == COMPANY ? setting.Lead_Company_Document_Master__c : null);
        }
        List<String> names = new List<String>();
        if (String.isBlank(masterName)) {
            return names;
        }
        for (Document_category__c category : [
            SELECT Name FROM Document_category__c WHERE Document_Master__r.Name = :masterName.trim() WITH SYSTEM_MODE ORDER BY CreatedDate, Name
        ]) {
            names.add(category.Name);
        }
        return names;
    }

    // The lead's documents (category folders), by name in small letters
    private static Map<String, Document__c> documentsOf(Id leadId) {
        Map<String, Document__c> documents = new Map<String, Document__c>();
        for (Document__c document : [
            SELECT Id, Name, Document_Id__c, OwnerId FROM Document__c WHERE Lead__c = :leadId WITH SYSTEM_MODE ORDER BY CreatedDate
        ]) {
            documents.put(document.Name.toLowerCase(), document);
        }
        return documents;
    }

    private static Map<Id, List<Sub_Document__c>> filesOf(List<Document__c> documents) {
        Map<Id, List<Sub_Document__c>> files = new Map<Id, List<Sub_Document__c>>();
        if (documents.isEmpty()) {
            return files;
        }
        for (Sub_Document__c file : [
            SELECT Id, Name, File_URL__c, CreatedDate, Document__c FROM Sub_Document__c WHERE Document__c IN :documents WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            if (!files.containsKey(file.Document__c)) {
                files.put(file.Document__c, new List<Sub_Document__c>());
            }
            files.get(file.Document__c).add(file);
        }
        return files;
    }

    // What is wrong with a file of this name and size, or null
    private static String fileProblem(String name, Long size) {
        String accepted = String.format(PARTNER_LEAD_DOCS_HINT.replace('\'', '\'\''), new List<Object>{ String.valueOf(maxSizeMb().intValue()) });
        if (String.isBlank(name) || !ALLOWED_TYPES.contains(extensionOf(name))) {
            return accepted;
        }
        if (size == null || size <= 0) {
            return PARTNER_LEAD_DOCS_UPLOAD_EXPIRED;
        }
        if (size > maxSizeMb() * 1024 * 1024) {
            return String.format(PARTNER_LEAD_DOCS_TOO_LARGE, new List<Object>{ name, String.valueOf(maxSizeMb().intValue()) });
        }
        return null;
    }

    private static Decimal maxSizeMb() {
        return setting == null || setting.Lead_Document_Max_MB__c == null || setting.Lead_Document_Max_MB__c <= 0
            ? DEFAULT_MAX_MB : setting.Lead_Document_Max_MB__c;
    }

    private static String extensionOf(String name) {
        return name == null || !name.contains('.') ? '' : name.substringAfterLast('.').toLowerCase();
    }

    private static Boolean containsIgnoreCase(List<String> names, String value) {
        for (String name : names) {
            if (name.equalsIgnoreCase(value)) {
                return true;
            }
        }
        return false;
    }

    // "<encrypted session>.<signature>", both base64url; only this class can read or make one
    @TestVisible
    private static String handleFor(UploadSession session) {
        Blob encrypted = Crypto.encryptWithManagedIV('AES256', signingKey(), Blob.valueOf(JSON.serialize(session)));
        String body = EncodingUtil.base64Encode(encrypted).replace('+', '-').replace('/', '_').replace('=', '');
        return body + '.' + signatureOf(body);
    }

    // The session behind a handle, which must belong to this lead
    private static UploadSession sessionOf(String handle, Id leadId) {
        UploadSession session;
        List<String> parts = String.isBlank(handle) ? new List<String>() : handle.split('\\.');
        if (parts.size() == 2 && signatureOf(parts[0]) == parts[1]) {
            try {
                String body = parts[0].replace('-', '+').replace('_', '/');
                while (Math.mod(body.length(), 4) != 0) {
                    body += '=';
                }
                Blob plain = Crypto.decryptWithManagedIV('AES256', signingKey(), EncodingUtil.base64Decode(body));
                session = (UploadSession) JSON.deserialize(plain.toString(), UploadSession.class);
            } catch (Exception e) {
                session = null;
            }
        }
        if (session == null || session.l != leadId || session.d == null || String.isBlank(session.u) || session.s == null || session.s <= 0) {
            throw userError(PARTNER_LEAD_DOCS_UPLOAD_EXPIRED);
        }
        return session;
    }

    private static String signatureOf(String claim) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf('lead-documents:' + claim), signingKey());
        return EncodingUtil.base64Encode(mac).replace('+', '-').replace('/', '_').replace('=', '');
    }

    // The random key of the protected custom setting Partner Registration Key (made on first use)
    private static Blob signingKey() {
        Partner_Registration_Key__c stored = Partner_Registration_Key__c.getOrgDefaults();
        if (String.isBlank(stored.Key__c)) {
            stored.Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
            upsert as system stored;
        }
        return EncodingUtil.base64Decode(stored.Key__c);
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}