// Channel partner registration from the Partner Portal's login page, which runs as the site's guest user.
//
// The form and what it saves are configured in custom metadata, not in code:
// - Partner Registration Field: one record per input of each registration type (label, input type, order, required)
//   with the Account and Contact fields that store its value. Hidden records write a fixed value on every registration.
// - Partner Registration Setting "Default": the record type, onboarding status and owner of new registrations, the
//   Account field that keeps the registration type, and the rules for documents.
//
// register() refuses an email that a channel partner account already has (on the account or one of its contacts).
// Otherwise it creates the partner's Account (always with the channel partner record type of the settings) and its
// Contact together with the first document, so that a registration is never saved without one, and answers with a
// signed ticket for the other documents, which follow one at a time (one request cannot carry several files).
//
// Where the documents go depends on the Document Master of the channel partner record type:
// - With categories (for example "BR, VAT Certificate" and "NIC, TIN and passport"), they go to SharePoint. The account
//   gets a folder with a sub-folder and a Document__c per category, and each document becomes a Sub Document with a
//   preview link in the category that its form's Documents input names. register() makes the folders and uploads the
//   first document before saving anything (no callout may follow DML); the others go through startDocumentUpload,
//   uploadDocumentChunk and finishDocumentUpload.
// - Without categories, they are Files on the account (Notes & Attachments); the others go through uploadDocument.
// Nothing is submitted for approval.
public without sharing class partnerPortalRegistrationController {

    public static final String REGISTERED = 'REGISTERED';
    public static final String INVALID = 'INVALID';

    @TestVisible
    private static final String SETTINGS_RECORD = 'Default';
    // An executive's email: their channel partner added them, so they log in once JKP approves them and never register
    private static final String EXECUTIVE_WAITING = 'Your channel partner has already added you, so you don\'t need to register. '
        + 'You will receive your login details by email once John Keells Properties approves you.';
    private static final String EXECUTIVE_LOG_IN = 'Your channel partner has already added you, so you don\'t need to register. Please log in instead.';

    // Input types of Partner Registration Field, and how the form shows each one
    private static final String TEXT_INPUT = 'Text';
    private static final String EMAIL_INPUT = 'Email';
    private static final String PHONE_INPUT = 'Phone';
    private static final String PROJECT_INPUT = 'Project';
    private static final String DOCUMENTS_INPUT = 'Documents';
    private static final String HIDDEN_INPUT = 'Hidden';
    private static final Map<String, String> FORM_TYPES = new Map<String, String>{
        TEXT_INPUT => 'text',
        EMAIL_INPUT => 'email',
        PHONE_INPUT => 'tel',
        PROJECT_INPUT => 'project',
        DOCUMENTS_INPUT => 'upload'
    };

    private static final Pattern EMAIL_FORMAT = Pattern.compile('^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$');
    private static final Pattern PHONE_FORMAT = Pattern.compile('^\\+?[0-9 ().-]+$');
    // Spaces of any kind at either end of a value, including no-break and zero-width ones
    private static final String EDGE_SPACES = '^[\\s\\p{Z}\\u200B-\\u200D\\u2060\\uFEFF]+|[\\s\\p{Z}\\u200B-\\u200D\\u2060\\uFEFF]+$';
    private static final Integer MIN_PHONE_DIGITS = 9;
    private static final Integer MAX_PHONE_DIGITS = 15;

    // How files of each type begin, in base64, so that a renamed file of another kind is refused
    private static final Map<String, String> FILE_SIGNATURES = new Map<String, String>{
        'pdf' => 'JVBER',
        'png' => 'iVBORw0KGgo',
        'jpg' => '/9j/',
        'jpeg' => '/9j/'
    };

    private static final String UPLOAD_CLOSED = 'This registration can no longer receive documents. Please contact the JKP CP team to send them.';
    // The page sends documents in chunks of 1.6 MB; nothing larger is accepted in one request
    private static final Integer MAX_CHUNK_BYTES = 4 * 1024 * 1024;

    // Tests replace the org's custom metadata with records of their own
    @TestVisible
    private static Partner_Registration_Setting__mdt setting;
    @TestVisible
    private static List<Partner_Registration_Field__mdt> fieldRecords;

    public class RegistrationForm {
        @AuraEnabled public List<RegistrationType> types = new List<RegistrationType>();
        // Extensions partners can upload (any file when empty), the largest file in MB and the most files
        @AuraEnabled public List<String> fileTypes;
        @AuraEnabled public Decimal maxFileSizeMb;
        @AuraEnabled public Integer maxFiles;
    }

    public class RegistrationType {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public List<FormField> fields = new List<FormField>();
    }

    public class FormField {
        @AuraEnabled public String name;
        // text, email, tel, project or upload
        @AuraEnabled public String type;
        @AuraEnabled public String label;
        @AuraEnabled public String placeholder;
        @AuraEnabled public String helpText;
        @AuraEnabled public String autocomplete;
        @AuraEnabled public Boolean required;
        // The length of the shortest field that stores the value
        @AuraEnabled public Integer maxLength;
        // The choices of a project field
        @AuraEnabled public List<Option> options;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    // A document the partner chose, checked before anything is saved. The registration carries the content of its first
    // document, which is saved with it; the others follow through uploadDocument.
    public class DocumentInfo {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Long size { get; set; }
        @AuraEnabled public String base64Data { get; set; }
    }

    public class RegistrationResult {
        // REGISTERED (with a ticket) or INVALID (with field errors)
        @AuraEnabled public String status;
        // Lets uploadDocument add this registration's documents
        @AuraEnabled public String ticket;
        // Problems by input name
        @AuraEnabled public Map<String, String> fieldErrors = new Map<String, String>();
        // The email belongs to a registration that is waiting for approval
        @AuraEnabled public Boolean pendingRegistration = false;
        // The other documents go to SharePoint (startDocumentUpload...) rather than uploadDocument
        @AuraEnabled public Boolean documentsInSharePoint = false;
    }

    // A configuration problem, which the admin fixes in the custom metadata
    private class SetupException extends Exception {}

    // A document that cannot be saved, with the reason to show the partner
    private class DocumentException extends Exception {}

    // A document's content (base64) that passed the checks, ready to be saved in SharePoint or as a File on an account.
    // It is decoded only when saved, so a large document is never held twice.
    private class DocumentFile {
        final String name;
        final String base64;

        DocumentFile(String name, String base64) {
            this.name = name;
            this.base64 = base64;
        }

        ContentVersion version(Id accountId, Id ownerId) {
            return new ContentVersion(
                Title = name.contains('.') ? name.substringBeforeLast('.') : name,
                PathOnClient = name,
                VersionData = EncodingUtil.base64Decode(base64),
                FirstPublishLocationId = accountId,
                OwnerId = ownerId
            );
        }
    }

    // A ticket's claims: the registration's account and, for SharePoint documents, the Document its uploads go to
    private class Ticket {
        Id accountId;
        Id documentId;
    }

    // A registration's documents in SharePoint: the account's folder with a sub-folder per Document category, and the
    // documents that came with the registration, uploaded into the folder of its form's category
    private class RegistrationFolders {
        final List<Document_Category__c> categories;
        final String uploadCategory;
        final List<DocumentFile> files;
        String rootFolderId;
        Id uploadDocumentId;
        final Map<String, String> folderIds = new Map<String, String>();
        final List<Sub_Document__c> uploaded = new List<Sub_Document__c>();

        RegistrationFolders(List<Document_Category__c> categories, String uploadCategory, List<DocumentFile> files) {
            this.categories = categories;
            this.uploadCategory = uploadCategory;
            this.files = files;
        }

        // Callouts only; nothing is saved yet
        void create(String accountName) {
            rootFolderId = SharePointDocumentManagerController.createFolder(null, accountName);
            for (Document_Category__c category : categories) {
                folderIds.put(category.Name.toLowerCase(), SharePointDocumentManagerController.createFolder(rootFolderId, category.Name));
            }
            String target = uploadCategory == null ? null : folderIds.get(uploadCategory.toLowerCase());
            for (DocumentFile file : files) {
                String itemId = SharePointDocumentManagerController.uploadBase64(target, file.name, file.base64, false);
                SharePointDocumentManagerController.UploadResult link = SharePointDocumentManagerController.linkFile(target, itemId);
                uploaded.add(new Sub_Document__c(
                    Name = (String.isNotBlank(link.storedName) ? link.storedName : file.name).left(80),
                    File_URL__c = link.fileUrl,
                    Public_Link__c = link.isPublic == true
                ));
            }
        }

        // A Document__c per category (its SharePoint folder) and a Sub Document per uploaded file, owned like the account
        void save(Id accountId, Id ownerId) {
            List<Document__c> documents = new List<Document__c>();
            for (Document_Category__c category : categories) {
                documents.add(new Document__c(
                    Name = category.Name,
                    Account__c = accountId,
                    Document_Id__c = folderIds.get(category.Name.toLowerCase()),
                    OwnerId = ownerId
                ));
            }
            insert as system documents;
            for (Document__c document : documents) {
                if (uploadCategory != null && document.Name.equalsIgnoreCase(uploadCategory)) {
                    uploadDocumentId = document.Id;
                }
            }
            for (Sub_Document__c subDocument : uploaded) {
                subDocument.Document__c = uploadDocumentId;
                subDocument.OwnerId = ownerId;
            }
            insert as system uploaded;
        }
    }

    // The form of each registration type, and the document rules
    @AuraEnabled(cacheable=true)
    public static RegistrationForm getRegistrationForm() {
        try {
            Partner_Registration_Setting__mdt config = settings();
            RegistrationForm form = new RegistrationForm();
            form.fileTypes = fileTypes(config);
            form.maxFileSizeMb = config.Max_File_Size_MB__c;
            form.maxFiles = config.Max_Files__c == null ? null : config.Max_Files__c.intValue();
            List<Option> projects;
            for (Schema.PicklistEntry entry : registrationTypes()) {
                RegistrationType type = new RegistrationType();
                type.label = entry.getLabel();
                type.value = entry.getValue();
                for (Input input : inputsFor(type.value)) {
                    if (input.kind == HIDDEN_INPUT) {
                        continue;
                    }
                    FormField field = input.formField();
                    if (input.kind == PROJECT_INPUT) {
                        projects = projects == null ? projectOptions() : projects;
                        field.options = projects;
                    }
                    type.fields.add(field);
                }
                if (!type.fields.isEmpty()) {
                    form.types.add(type);
                }
            }
            return form;
        } catch (SetupException e) {
            throw userError(e.getMessage());
        }
    }

    // Creates the partner's Account and Contact from the form's values, once every value and document passes its checks
    @AuraEnabled
    public static RegistrationResult register(String registrationType, Map<String, String> values, List<DocumentInfo> documents) {
        try {
            return save(
                registrationType,
                values == null ? new Map<String, String>() : values,
                documents == null ? new List<DocumentInfo>() : documents
            );
        } catch (SetupException e) {
            throw userError(e.getMessage());
        }
    }

    // Saves one document of a registration as a File on its Account
    @AuraEnabled
    public static void uploadDocument(String ticket, String fileName, String base64Data) {
        try {
            saveDocument(ticket, fileName, base64Data);
        } catch (SetupException e) {
            throw userError(e.getMessage());
        }
    }

    // The channel partner Account record type of the Partner Registration Setting. Every registration gets it, the
    // duplicate email check looks only at accounts that have it, and only partners whose account has it can log in.
    // Null when it is not set up as an active Account record type.
    public static Id partnerRecordTypeId() {
        Partner_Registration_Setting__mdt config = loadSettings();
        if (config == null || String.isBlank(config.Account_Record_Type__c)) {
            return null;
        }
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(config.Account_Record_Type__c.trim());
        return info == null || !info.isActive() ? null : info.getRecordTypeId();
    }

    // The Onboarding Status of registrations waiting for approval, or null when none is set up
    public static String registrationStatus() {
        Partner_Registration_Setting__mdt config = loadSettings();
        return config == null || String.isBlank(config.Registration_Status__c) ? null : config.Registration_Status__c.trim();
    }

    // The Onboarding Status of rejected registrations (Partner Registration Setting), whose email may register again
    public static String rejectedStatus() {
        Partner_Registration_Setting__mdt config = loadSettings();
        return config == null || String.isBlank(config.Rejected_Status__c) ? null : config.Rejected_Status__c.trim();
    }

    private static RegistrationResult save(String registrationType, Map<String, String> values, List<DocumentInfo> documents) {
        Partner_Registration_Setting__mdt config = settings();
        String type = registrationTypeNamed(registrationType);
        if (type == null) {
            throw userError('Choose a registration type.');
        }

        Account partnerAccount = new Account();
        Contact partnerContact = new Contact();
        Map<Schema.SObjectType, SObject> records = new Map<Schema.SObjectType, SObject>{
            Account.SObjectType => partnerAccount,
            Contact.SObjectType => partnerContact
        };
        RegistrationResult result = new RegistrationResult();
        List<Input> emailInputs = new List<Input>();
        Set<String> emails = new Set<String>();
        List<DocumentFile> files = new List<DocumentFile>();
        List<Option> projects;
        for (Input input : inputsFor(type)) {
            if (input.kind == HIDDEN_INPUT) {
                input.writeDefault(records);
                continue;
            }
            String problem;
            if (input.kind == DOCUMENTS_INPUT) {
                problem = documentsProblem(input, documents, config);
                if (problem == null) {
                    try {
                        files = documentFiles(documents, config);
                    } catch (DocumentException e) {
                        problem = e.getMessage();
                    }
                }
                // A required upload needs a document that is actually saved with the registration
                if (problem == null && files.isEmpty() && input.record.Required__c == true) {
                    problem = 'Upload at least one document.';
                }
            } else {
                String value = cleanValue(values.get(input.name));
                if (input.kind == PROJECT_INPUT && String.isNotBlank(value)) {
                    projects = projects == null ? projectOptions() : projects;
                }
                problem = input.problem(value, projects);
                if (problem == null && String.isNotBlank(value)) {
                    problem = input.write(records, value);
                    if (input.kind == EMAIL_INPUT) {
                        emailInputs.add(input);
                        emails.add(value.toLowerCase());
                    }
                }
            }
            if (problem != null) {
                result.fieldErrors.put(input.name, problem);
            }
        }

        // One channel partner account per email: checked whenever the email itself is valid, so that the partner sees
        // this together with any other problem
        Id recordTypeId = recordTypeId(config);
        if (!emails.isEmpty()) {
            Account existing = existingPartner(emailInputs, emails, recordTypeId, registrationStatus());
            if (existing != null) {
                String message;
                if (existing.Channel_Head__c != null) {
                    // An executive: added by their channel partner and approved by JKP, never registered by themselves
                    message = canLogIn(emails, recordTypeId) ? EXECUTIVE_LOG_IN : EXECUTIVE_WAITING;
                } else if (registrationStatus() != null && existing.Onboarding_Status__c == registrationStatus()) {
                    result.pendingRegistration = true;
                    message = 'A registration with this email is already waiting for approval.';
                } else if (canLogIn(emails, recordTypeId)) {
                    // Only an email that is itself a working partner login can be logged in with
                    message = 'This email is already registered. Please log in instead.';
                } else {
                    message = 'This email was used for an earlier registration. Please contact the JKP CP team.';
                }
                for (Input input : emailInputs) {
                    result.fieldErrors.put(input.name, message);
                }
            }
        }
        if (!result.fieldErrors.isEmpty()) {
            result.status = INVALID;
            return result;
        }

        Id ownerId = ownerId(config);
        partnerAccount.OwnerId = ownerId;
        partnerContact.OwnerId = ownerId;
        partnerAccount.RecordTypeId = recordTypeId;
        if (registrationStatus() != null) {
            partnerAccount.Onboarding_Status__c = registrationStatus();
        }
        if (String.isNotBlank(config.Registration_Type_Field__c)) {
            Target typeField = new Target(Account.SObjectType, config.Registration_Type_Field__c.trim(), 'Partner Registration Setting ' + SETTINGS_RECORD);
            typeField.write(partnerAccount, type);
        }

        // SharePoint comes first: no callout may follow DML. If it fails, nothing is saved and the partner can try again.
        RegistrationFolders folders = registrationFolders(type, recordTypeId, files);
        if (folders != null) {
            try {
                folders.create(partnerAccount.Name);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Partner registration could not store its documents in SharePoint: ' + e.getMessage());
                throw userError('Your documents could not be stored right now. Please try again in a few minutes.');
            }
            // The account already has its folder, so the account trigger does not queue another
            partnerAccount.Document_Id__c = folders.rootFolderId;
        }

        Database.DMLOptions options = new Database.DMLOptions();
        options.OptAllOrNone = true;
        // Duplicate rules that only alert do not stop a registration; the team still sees the alert in Salesforce
        options.DuplicateRuleHeader.allowSave = true;
        try {
            Database.insert(partnerAccount, options, AccessLevel.SYSTEM_MODE);
            partnerContact.AccountId = partnerAccount.Id;
            Database.insert(partnerContact, options, AccessLevel.SYSTEM_MODE);
            if (folders != null) {
                folders.save(partnerAccount.Id, ownerId);
            } else {
                List<ContentVersion> versions = new List<ContentVersion>();
                for (DocumentFile file : files) {
                    versions.add(file.version(partnerAccount.Id, ownerId));
                }
                insert as system versions;
            }
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'Partner registration could not be saved: ' + e.getMessage());
            throw userError('Your registration could not be saved: ' + e.getDmlMessage(0));
        }
        // The CP Manager's approval: if it cannot be asked for, nothing is saved and the partner can try again
        submitForApproval(config, partnerAccount.Id, ownerId);

        Decimal window = config.Upload_Window_Minutes__c;
        result.status = REGISTERED;
        result.documentsInSharePoint = folders != null;
        result.ticket = ticketFor(partnerAccount.Id, folders == null ? null : folders.uploadDocumentId,
            window == null ? null : Datetime.now().addMinutes(window.intValue()));
        return result;
    }

    // The SharePoint layout of a registration, or null when the record type's Document Master has no categories
    private static RegistrationFolders registrationFolders(String registrationType, Id recordTypeId, List<DocumentFile> files) {
        String recordTypeName = Schema.SObjectType.Account.getRecordTypeInfosById().get(recordTypeId).getName();
        List<Document_Category__c> categories = DocumentCreationHandler.categoriesForRecordType(recordTypeName);
        if (categories.isEmpty()) {
            return null;
        }
        String category = uploadCategory(registrationType);
        if (category != null) {
            Boolean known = false;
            for (Document_Category__c candidate : categories) {
                known = known || candidate.Name.equalsIgnoreCase(category);
            }
            if (!known) {
                throw new SetupException('Partner registration is not set up: the Documents input of the ' + registrationType
                    + ' form names the Document category "' + category + '", which the ' + recordTypeName + ' Document Master does not have.');
            }
        }
        return new RegistrationFolders(categories, category, files);
    }

    // The Document category whose folder receives a registration type's documents (the Document Category of its
    // Documents input); null when the form has no Documents input
    private static String uploadCategory(String registrationType) {
        for (Input input : inputsFor(registrationType)) {
            if (input.kind == DOCUMENTS_INPUT) {
                if (String.isBlank(input.record.Document_Category__c)) {
                    throw new SetupException('Partner registration is not set up: give the Documents input of the ' + registrationType
                        + ' form (' + input.describe() + ') a Document Category.');
                }
                return input.record.Document_Category__c.trim();
            }
        }
        return null;
    }

    // ---------- documents after the first, in SharePoint: start, send in chunks, finish ----------
    //
    // The browser never sees SharePoint's upload URL: anyone holding that URL could upload any size or kind of file
    // straight to the folder. It gets an opaque handle instead (the URL, the Document, the accepted size and name,
    // encrypted and signed with the registration key), and every chunk passes through uploadDocumentChunk's checks.

    // An upload session the page holds as a handle
    private class UploadSession {
        String u;   // SharePoint's upload URL
        Id d;       // the Document whose folder it uploads into
        Long s;     // the size accepted at the start
        String n;   // the file name
    }

    // Starts the upload of one more document into the registration's SharePoint folder and returns its handle
    @AuraEnabled
    public static String startDocumentUpload(String ticket, String fileName, Long size) {
        try {
            Partner_Registration_Setting__mdt config = settings();
            Document__c folder = uploadFolder(ticket);
            String name = cleanFileName(fileName);
            String problem = size == null || size <= 0 ? name + ' is empty.' : fileProblem(name, size, config);
            if (problem != null) {
                throw userError(problem);
            }
            checkDocumentCount(folder, config);
            UploadSession session = new UploadSession();
            session.u = SharePointDocumentManagerController.startUploadSession(folder.Document_Id__c, name, false);
            session.d = folder.Id;
            session.s = size;
            session.n = name;
            return handleFor(session);
        } catch (SetupException e) {
            throw userError(e.getMessage());
        }
    }

    // Sends one chunk of a document that startDocumentUpload began. The chunk must fit the size accepted at the start,
    // the first one must look like the file type its name says, and the last one is refused once the folder is full.
    @AuraEnabled
    public static SharePointDocumentManagerController.ChunkResult uploadDocumentChunk(String ticket, String handle,
            String base64Chunk, Long startByte, Long endByte) {
        try {
            Partner_Registration_Setting__mdt config = settings();
            Document__c folder = uploadFolder(ticket);
            UploadSession session = sessionOf(handle, folder.Id);
            Blob bytes;
            try {
                bytes = EncodingUtil.base64Decode(base64Chunk == null ? '' : base64Chunk);
            } catch (Exception e) {
                bytes = null;
            }
            if (bytes == null || startByte == null || endByte == null || startByte < 0 || endByte > session.s
                    || bytes.size() == 0 || bytes.size() > MAX_CHUNK_BYTES || bytes.size() != endByte - startByte) {
                throw userError(session.n + ' could not be sent. Please choose it again.');
            }
            String signature = FILE_SIGNATURES.get(extensionOf(session.n));
            if (startByte == 0 && signature != null && !base64Chunk.startsWith(signature)) {
                throw userError(session.n + ' is not a valid ' + extensionOf(session.n).toUpperCase() + ' file.');
            }
            if (endByte == session.s) {
                checkDocumentCount(folder, config);
            }
            return SharePointDocumentManagerController.uploadBytes(session.u, bytes, startByte, endByte, session.s);
        } catch (SetupException e) {
            throw userError(e.getMessage());
        }
    }

    // Finishes a document: checks that SharePoint has it in the registration's folder, gives it a preview link and saves
    // its Sub Document (callouts first, then the record). Finishing the same file again changes nothing, so the page can
    // safely retry after a dropped connection.
    @AuraEnabled
    public static void finishDocumentUpload(String ticket, String handle, String itemId) {
        try {
            Partner_Registration_Setting__mdt config = settings();
            Document__c folder = uploadFolder(ticket);
            UploadSession session = sessionOf(handle, folder.Id);
            SharePointDocumentManagerController.UploadResult link = SharePointDocumentManagerController.linkFile(folder.Document_Id__c, itemId);
            if ([SELECT COUNT() FROM Sub_Document__c WHERE Document__c = :folder.Id AND File_URL__c = :link.fileUrl WITH SYSTEM_MODE] > 0) {
                return;
            }
            if (config.Max_Files__c != null
                && [SELECT COUNT() FROM Sub_Document__c WHERE Document__r.Account__c = :folder.Account__c WITH SYSTEM_MODE] >= config.Max_Files__c) {
                throw userError('This registration already has ' + config.Max_Files__c.intValue() + ' documents, the most allowed.');
            }
            insert as system new Sub_Document__c(
                Name = (String.isNotBlank(link.storedName) ? link.storedName : session.n).left(80),
                Document__c = folder.Id,
                File_URL__c = link.fileUrl,
                Public_Link__c = link.isPublic == true,
                OwnerId = folder.OwnerId
            );
        } catch (SetupException e) {
            throw userError(e.getMessage());
        }
    }

    // "<encrypted session>.<signature>", both base64url; only this class can read or make one
    @TestVisible
    private static String handleFor(Object sessionObject) {
        UploadSession session = (UploadSession) sessionObject;
        Blob encrypted = Crypto.encryptWithManagedIV('AES256', signingKey(), Blob.valueOf(JSON.serialize(session)));
        String body = EncodingUtil.base64Encode(encrypted).replace('+', '-').replace('/', '_').replace('=', '');
        return body + '.' + signatureOf(body);
    }

    @TestVisible
    private static String handleFor(String uploadUrl, Id documentId, Long size, String name) {
        UploadSession session = new UploadSession();
        session.u = uploadUrl;
        session.d = documentId;
        session.s = size;
        session.n = name;
        return handleFor(session);
    }

    // The session behind a handle, which must belong to this Document
    private static UploadSession sessionOf(String handle, Id documentId) {
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
        if (session == null || session.d != documentId || String.isBlank(session.u) || session.s == null || session.s <= 0) {
            throw userError('This upload is no longer valid. Please choose the document again.');
        }
        return session;
    }

    // Refuses another document once the registration's folder holds the most allowed, counting the files SharePoint
    // really has (a started upload that was never finished still counts once it is complete)
    private static void checkDocumentCount(Document__c folder, Partner_Registration_Setting__mdt config) {
        if (config.Max_Files__c != null && SharePointDocumentManagerController.countFiles(folder.Document_Id__c) >= config.Max_Files__c) {
            throw userError('This registration already has ' + config.Max_Files__c.intValue() + ' documents, the most allowed.');
        }
    }

    // The Document (SharePoint folder) a registration's ticket uploads into, while the registration waits for approval
    private static Document__c uploadFolder(String ticket) {
        Ticket claim = ticketOf(ticket);
        if (claim == null || claim.documentId == null) {
            throw userError(UPLOAD_CLOSED);
        }
        List<Account> accounts = [SELECT Onboarding_Status__c FROM Account WHERE Id = :claim.accountId WITH SYSTEM_MODE];
        if (accounts.isEmpty() || (registrationStatus() != null && accounts[0].Onboarding_Status__c != registrationStatus())) {
            throw userError(UPLOAD_CLOSED);
        }
        List<Document__c> folders = [
            SELECT Id, Account__c, Document_Id__c, OwnerId
            FROM Document__c
            WHERE Id = :claim.documentId AND Account__c = :claim.accountId
            WITH SYSTEM_MODE
        ];
        if (folders.isEmpty() || String.isBlank(folders[0].Document_Id__c)) {
            throw userError(UPLOAD_CLOSED);
        }
        return folders[0];
    }

    private static void saveDocument(String ticket, String fileName, String base64Data) {
        Partner_Registration_Setting__mdt config = settings();
        Ticket claim = ticketOf(ticket);
        // A registration whose documents go to SharePoint uploads them with startDocumentUpload instead
        Id accountId = claim == null || claim.documentId != null ? null : claim.accountId;
        List<Account> accounts = accountId == null
            ? new List<Account>()
            // Locked, so uploads for one registration take turns and each count sees the files already saved
            : [SELECT Id, OwnerId, Onboarding_Status__c FROM Account WHERE Id = :accountId WITH SYSTEM_MODE FOR UPDATE];
        // Only while the registration waits for approval
        if (accounts.isEmpty() || (registrationStatus() != null && accounts[0].Onboarding_Status__c != registrationStatus())) {
            throw userError(UPLOAD_CLOSED);
        }

        DocumentFile file;
        try {
            file = documentFile(fileName, base64Data, config);
        } catch (DocumentException e) {
            throw userError(e.getMessage());
        }
        if (config.Max_Files__c != null
            && [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :accountId WITH SYSTEM_MODE] >= config.Max_Files__c) {
            throw userError('This registration already has ' + config.Max_Files__c.intValue() + ' documents, the most allowed.');
        }
        insert as system file.version(accountId, accounts[0].OwnerId);
    }

    // The new registration goes to the Approval Process of the settings; if that cannot be asked for, nothing is saved
    private static void submitForApproval(Partner_Registration_Setting__mdt config, Id accountId, Id ownerId) {
        if (!sendForApproval(accountId, ownerId, 'Submitted automatically from the Partner Portal registration form.')) {
            throw userError('Your registration could not be sent for approval right now. Please try again in a few minutes.');
        }
    }

    // Sends a waiting channel partner account to the Approval Process of the settings (none when it is blank), on behalf
    // of the record owner, an allowed submitter of the process: a registration from the form, or an executive added by
    // its channel head (partnerWebPortalMyTeamController). True when the request was made or no process is set up,
    // false when it could not be made.
    public static Boolean sendForApproval(Id accountId, Id ownerId, String comments) {
        Partner_Registration_Setting__mdt config = loadSettings();
        if (config == null || String.isBlank(config.Approval_Process__c)) {
            return true;
        }
        Approval.ProcessSubmitRequest submission = new Approval.ProcessSubmitRequest();
        submission.setObjectId(accountId);
        submission.setProcessDefinitionNameOrId(config.Approval_Process__c.trim());
        submission.setSubmitterId(ownerId);
        submission.setComments(comments);
        try {
            Approval.ProcessResult outcome = Approval.process(submission);
            if (!outcome.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Channel partner account ' + accountId + ' could not be submitted for approval: ' + outcome.getErrors());
                return false;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Channel partner account ' + accountId + ' could not be submitted for approval: ' + e.getMessage());
            return false;
        }
        return true;
    }

    // ---------- configuration ----------

    private static Partner_Registration_Setting__mdt loadSettings() {
        if (setting == null) {
            setting = Partner_Registration_Setting__mdt.getInstance(SETTINGS_RECORD);
        }
        return setting;
    }

    private static Partner_Registration_Setting__mdt settings() {
        Partner_Registration_Setting__mdt config = loadSettings();
        if (config == null) {
            throw new SetupException('Partner registration is not set up: the Partner Registration Setting ' + SETTINGS_RECORD + ' is missing.');
        }
        return config;
    }

    // The registration types, in the order of the Registration Type picklist of Partner Registration Field
    private static List<Schema.PicklistEntry> registrationTypes() {
        List<Schema.PicklistEntry> types = new List<Schema.PicklistEntry>();
        for (Schema.PicklistEntry entry : Partner_Registration_Field__mdt.Registration_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                types.add(entry);
            }
        }
        return types;
    }

    // The registration type with this value (in any case), or null
    private static String registrationTypeNamed(String value) {
        for (Schema.PicklistEntry entry : registrationTypes()) {
            if (String.isNotBlank(value) && entry.getValue().equalsIgnoreCase(value.trim())) {
                return entry.getValue();
            }
        }
        return null;
    }

    // The active inputs of a registration type: its own and those for every type, in form order
    private static List<Input> inputsFor(String registrationType) {
        if (fieldRecords == null) {
            fieldRecords = [
                SELECT DeveloperName, MasterLabel, Registration_Type__c, Input_Name__c, Input_Type__c, Field_Label__c,
                    Placeholder__c, Help_Text__c, Autocomplete__c, Required__c, Order__c, Account_Field__c,
                    Contact_Field__c, Default_Value__c, Active__c, Document_Category__c
                FROM Partner_Registration_Field__mdt
                WITH SYSTEM_MODE
                ORDER BY Order__c
            ];
        }
        List<Input> inputs = new List<Input>();
        Set<String> names = new Set<String>();
        for (Partner_Registration_Field__mdt record : fieldRecords) {
            if (record.Active__c != true || (String.isNotBlank(record.Registration_Type__c) && record.Registration_Type__c != registrationType)) {
                continue;
            }
            Input input = new Input(record);
            if (input.kind != HIDDEN_INPUT && !names.add(input.name.toLowerCase())) {
                throw new SetupException(input.describe() + ' uses the Input Name ' + input.name + ', which another ' + registrationType + ' field already uses.');
            }
            inputs.add(input);
        }
        return inputs;
    }

    // The channel partner record type, which every registration must get
    private static Id recordTypeId(Partner_Registration_Setting__mdt config) {
        Id recordTypeId = partnerRecordTypeId();
        if (recordTypeId == null) {
            throw new SetupException('Partner registration is not set up: the Account Record Type of the Partner Registration Setting ('
                + (String.isBlank(config.Account_Record_Type__c) ? 'blank' : config.Account_Record_Type__c)
                + ') must be an active Account record type.');
        }
        return recordTypeId;
    }

    // The Record Owner of the settings; failing that, the default owner of records created by this site's guest user
    private static Id ownerId(Partner_Registration_Setting__mdt config) {
        if (String.isNotBlank(config.Record_Owner__c)) {
            List<User> owners = [
                SELECT Id
                FROM User
                WHERE Username = :config.Record_Owner__c.trim() AND IsActive = true AND UserType = 'Standard'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (owners.isEmpty()) {
                throw new SetupException('Partner registration is not set up: the Record Owner ' + config.Record_Owner__c + ' is not an active internal user.');
            }
            return owners[0].Id;
        }
        List<Site> sites = [
            SELECT GuestRecordDefaultOwnerId
            FROM Site
            WHERE GuestUserId = :UserInfo.getUserId() AND GuestRecordDefaultOwnerId != null
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (sites.isEmpty()) {
            throw new SetupException('Partner registration is not set up: give the Partner Registration Setting a Record Owner, or the site a default owner for guest records.');
        }
        return sites[0].GuestRecordDefaultOwnerId;
    }

    // ---------- checks ----------

    // A channel partner account that already has one of these emails in a field the email inputs fill, on the account
    // itself or on one of its contacts. Accounts of other record types (customers) do not count. A pending one is preferred.
    private static Account existingPartner(List<Input> emailInputs, Set<String> emails, Id recordTypeId, String pendingStatus) {
        Set<String> accountFields = new Set<String>();
        Set<String> contactFields = new Set<String>();
        for (Input input : emailInputs) {
            for (Target target : input.targets) {
                if (target.field != null) {
                    (target.objectType == Account.SObjectType ? accountFields : contactFields).add(target.field.getName());
                }
            }
        }
        Map<String, Object> binds = new Map<String, Object>{ 'emails' => emails, 'partnerType' => recordTypeId };
        List<Account> found = new List<Account>();
        for (String field : contactFields) {
            for (Contact match : (List<Contact>) Database.queryWithBinds(
                'SELECT Account.Id, Account.Onboarding_Status__c, Account.Channel_Head__c FROM Contact WHERE Account.RecordTypeId = :partnerType AND '
                    + field + ' IN :emails LIMIT 20',
                binds,
                AccessLevel.SYSTEM_MODE
            )) {
                found.add(match.Account);
            }
        }
        for (String field : accountFields) {
            found.addAll((List<Account>) Database.queryWithBinds(
                'SELECT Id, Onboarding_Status__c, Channel_Head__c FROM Account WHERE RecordTypeId = :partnerType AND ' + field + ' IN :emails LIMIT 20',
                binds,
                AccessLevel.SYSTEM_MODE
            ));
        }
        String rejected = rejectedStatus();
        Account existing;
        for (Account candidate : found) {
            // A rejected registration does not keep its email: the partner may register again, for a new approval
            if (rejected != null && candidate.Onboarding_Status__c == rejected) {
                continue;
            }
            if (existing == null || (pendingStatus != null && candidate.Onboarding_Status__c == pendingStatus)) {
                existing = candidate;
            }
        }
        return existing;
    }

    private static String documentsProblem(Input input, List<DocumentInfo> documents, Partner_Registration_Setting__mdt config) {
        if (documents.isEmpty()) {
            return input.record.Required__c == true ? 'Upload at least one document.' : null;
        }
        if (config.Max_Files__c != null && documents.size() > config.Max_Files__c) {
            return 'Upload up to ' + config.Max_Files__c.intValue() + ' documents.';
        }
        for (DocumentInfo document : documents) {
            String problem = document == null ? null : fileProblem(cleanFileName(document.name), document.size, config);
            if (problem != null) {
                return problem;
            }
        }
        return null;
    }

    // The documents of a registration that carry their content (the client sends the first one's)
    private static List<DocumentFile> documentFiles(List<DocumentInfo> documents, Partner_Registration_Setting__mdt config) {
        List<DocumentFile> files = new List<DocumentFile>();
        for (DocumentInfo document : documents) {
            if (document != null && String.isNotBlank(document.base64Data)) {
                files.add(documentFile(document.name, document.base64Data, config));
            }
        }
        return files;
    }

    // A document's content once it can be read, its type is allowed and matches what is inside, and it is not too large
    private static DocumentFile documentFile(String fileName, String base64Data, Partner_Registration_Setting__mdt config) {
        String name = cleanFileName(fileName);
        String data = base64Data == null ? '' : base64Data;
        Long size = base64Size(data);
        if (size <= 0) {
            throw new DocumentException(name + ' could not be read. Please choose it again.');
        }
        String problem = fileProblem(name, size, config);
        String signature = FILE_SIGNATURES.get(extensionOf(name));
        if (problem == null && signature != null && !data.startsWith(signature)) {
            problem = name + ' is not a valid ' + extensionOf(name).toUpperCase() + ' file.';
        }
        if (problem != null) {
            throw new DocumentException(problem);
        }
        return new DocumentFile(name, data);
    }

    // The number of bytes a base64 text holds, or 0 when it is not base64. Only its first characters and its end are
    // decoded here; the whole text is decoded, a slice at a time, when the document is saved.
    private static Long base64Size(String data) {
        if (String.isBlank(data) || Math.mod(data.length(), 4) != 0) {
            return 0;
        }
        try {
            if (EncodingUtil.base64Decode(data.left(4096)).size() == 0 || EncodingUtil.base64Decode(data.right(4)).size() == 0) {
                return 0;
            }
        } catch (Exception e) {
            return 0;
        }
        return (Long) (data.length() / 4) * 3 - (data.endsWith('==') ? 2 : (data.endsWith('=') ? 1 : 0));
    }

    // A file of a type that is not allowed, or larger than allowed
    private static String fileProblem(String name, Long size, Partner_Registration_Setting__mdt config) {
        List<String> types = fileTypes(config);
        if (!types.isEmpty() && !types.contains(extensionOf(name))) {
            return name + ' is not a ' + typesText(types) + ' file.';
        }
        Decimal maxMb = config.Max_File_Size_MB__c;
        if (size != null && maxMb != null && size > maxMb * 1024 * 1024) {
            return name + ' is larger than ' + maxMb.stripTrailingZeros().toPlainString() + ' MB.';
        }
        return null;
    }

    // The allowed file extensions, lower case without dots
    private static List<String> fileTypes(Partner_Registration_Setting__mdt config) {
        List<String> types = new List<String>();
        for (String type : (config.Allowed_File_Types__c == null ? '' : config.Allowed_File_Types__c).split('[,;\\s]+')) {
            String extension = type.trim().removeStart('.').toLowerCase();
            if (String.isNotBlank(extension) && !types.contains(extension)) {
                types.add(extension);
            }
        }
        return types;
    }

    // "PDF", or "PDF, JPG or PNG"
    private static String typesText(List<String> types) {
        List<String> names = new List<String>();
        for (String type : types) {
            names.add(type.toUpperCase());
        }
        if (names.size() == 1) {
            return names[0];
        }
        String last = names.remove(names.size() - 1);
        return String.join(names, ', ') + ' or ' + last;
    }

    private static String extensionOf(String name) {
        return name != null && name.contains('.') ? name.substringAfterLast('.').toLowerCase() : '';
    }

    // A plain file name: no folders, control characters or characters that files cannot have, at most 255 characters.
    // Line breaks and other control characters go first, so that no folder part can hide behind one.
    private static String cleanFileName(String fileName) {
        String name = (fileName == null ? '' : fileName).replaceAll('[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]', '_');
        name = name.replaceAll('^.*[\\\\/]', '').replaceAll('[:*?"<>|]', '_').trim();
        if (String.isBlank(name)) {
            name = 'Document';
        }
        if (name.length() > 255) {
            String extension = extensionOf(name);
            name = String.isBlank(extension) ? name.left(255) : name.left(254 - extension.length()) + '.' + extension;
        }
        return name;
    }

    // A value without the spaces at its ends, whatever their kind, so that invisible characters cannot fill a field
    private static String cleanValue(String value) {
        return value == null ? '' : value.replaceAll(EDGE_SPACES, '');
    }

    // Whether one of these emails logs in to the portal: an active partner user on a channel partner account has it as
    // username or email (the users the login page accepts). A company's general email, or a second contact without a
    // login, does not: logging in with it would only lead back to registration.
    private static Boolean canLogIn(Set<String> emails, Id partnerType) {
        return [
            SELECT COUNT()
            FROM User
            WHERE UserType = 'PowerPartner' AND IsActive = true AND Contact.Account.RecordTypeId = :partnerType
                AND (Username IN :emails OR Email IN :emails)
            WITH SYSTEM_MODE
        ] > 0;
    }

    // Digits with spaces, brackets, dashes or dots and an optional leading +, holding 9 to 15 digits without a leading 0
    private static Boolean isPhone(String value) {
        if (!PHONE_FORMAT.matcher(value).matches()) {
            return false;
        }
        String digits = value.replaceAll('[^0-9]', '').replaceFirst('^0+', '');
        return digits.length() >= MIN_PHONE_DIGITS && digits.length() <= MAX_PHONE_DIGITS;
    }

    // Active projects, for a Project input
    private static List<Option> projectOptions() {
        List<Option> options = new List<Option>();
        for (Project__c project : [
            SELECT Id, Name
            FROM Project__c
            WHERE Active__c = true
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 200
        ]) {
            Option option = new Option();
            option.label = project.Name;
            option.value = project.Id;
            options.add(option);
        }
        return options;
    }

    // "Kamal Perera" -> Kamal / Perera. A long name keeps as many words as fit in the first part; the rest is the last.
    private static List<String> splitName(String fullName, Integer firstLength, Integer lastLength) {
        String name = fullName.normalizeSpace();
        Integer cut = name.lastIndexOf(' ');
        while (cut > firstLength) {
            cut = name.lastIndexOf(' ', cut - 1);
        }
        if (cut <= 0) {
            return new List<String>{ null, name.left(lastLength) };
        }
        return new List<String>{ name.left(cut), name.substring(cut + 1).left(lastLength) };
    }

    // ---------- upload tickets ----------

    // "<account id>.<document id, or - for Files>.<expiry in ms, 0 for none>.<signature>"
    @TestVisible
    private static String ticketFor(Id accountId, Id documentId, Datetime expires) {
        String claim = accountId + '.' + (documentId == null ? '-' : String.valueOf(documentId)) + '.' + (expires == null ? 0 : expires.getTime());
        return claim + '.' + signatureOf(claim);
    }

    @TestVisible
    private static String ticketFor(Id accountId, Datetime expires) {
        return ticketFor(accountId, null, expires);
    }

    // The claims of a ticket from register(), while the ticket is valid
    private static Ticket ticketOf(String ticket) {
        List<String> parts = String.isBlank(ticket) ? new List<String>() : ticket.split('\\.');
        if (parts.size() != 4 || signatureOf(parts[0] + '.' + parts[1] + '.' + parts[2]) != parts[3]) {
            return null;
        }
        try {
            Long expires = Long.valueOf(parts[2]);
            if (expires != 0 && Datetime.now().getTime() > expires) {
                return null;
            }
            Ticket claim = new Ticket();
            claim.accountId = Id.valueOf(parts[0]);
            claim.documentId = parts[1] == '-' ? null : Id.valueOf(parts[1]);
            return claim;
        } catch (Exception e) {
            return null;
        }
    }

    private static String signatureOf(String claim) {
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(claim), signingKey());
        return EncodingUtil.base64Encode(mac).replace('+', '-').replace('/', '_').replace('=', '');
    }

    // A random key in the protected custom setting Partner Registration Key, made on first use
    private static Blob signingKey() {
        Partner_Registration_Key__c stored = Partner_Registration_Key__c.getOrgDefaults();
        if (String.isBlank(stored.Key__c)) {
            stored.Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
            upsert as system stored;
        }
        return EncodingUtil.base64Decode(stored.Key__c);
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    // ---------- inputs and the fields they fill ----------

    // A Partner Registration Field record, with the Account and Contact fields that store its value
    private class Input {
        final Partner_Registration_Field__mdt record;
        final String name;
        final String kind;
        final List<Target> targets = new List<Target>();

        Input(Partner_Registration_Field__mdt record) {
            this.record = record;
            this.kind = record.Input_Type__c;
            this.name = String.isBlank(record.Input_Name__c) ? record.DeveloperName : record.Input_Name__c.trim();
            if (kind != HIDDEN_INPUT && !FORM_TYPES.containsKey(kind)) {
                throw new SetupException(describe() + ' has an unknown Input Type: ' + kind + '.');
            }
            addTargets(Account.SObjectType, record.Account_Field__c);
            addTargets(Contact.SObjectType, record.Contact_Field__c);
        }

        String describe() {
            return 'Partner Registration Field ' + record.DeveloperName;
        }

        void addTargets(Schema.SObjectType objectType, String apiNames) {
            for (String apiName : (apiNames == null ? '' : apiNames).split(',')) {
                if (String.isNotBlank(apiName)) {
                    targets.add(new Target(objectType, apiName.trim(), describe()));
                }
            }
        }

        // The length of the shortest text field that stores the value
        Integer maxLength() {
            Integer shortest;
            for (Target target : targets) {
                Integer length = target.maxLength();
                if (length != null && (shortest == null || length < shortest)) {
                    shortest = length;
                }
            }
            return shortest;
        }

        FormField formField() {
            FormField field = new FormField();
            field.name = name;
            field.type = FORM_TYPES.get(kind);
            field.label = String.isBlank(record.Field_Label__c) ? record.MasterLabel : record.Field_Label__c;
            field.placeholder = record.Placeholder__c;
            field.helpText = record.Help_Text__c;
            field.autocomplete = record.Autocomplete__c;
            field.required = record.Required__c == true;
            field.maxLength = kind == PROJECT_INPUT || kind == DOCUMENTS_INPUT ? null : maxLength();
            return field;
        }

        // What is wrong with a value the partner gave, or null
        String problem(String value, List<Option> projects) {
            if (String.isBlank(value)) {
                return record.Required__c != true ? null : (kind == PROJECT_INPUT ? 'Choose a project.' : 'This field is required.');
            }
            Integer max = maxLength();
            if (kind != PROJECT_INPUT && max != null && value.length() > max) {
                return 'Use ' + max + ' characters or fewer.';
            }
            if (kind == EMAIL_INPUT && !EMAIL_FORMAT.matcher(value).matches()) {
                return 'Enter a valid email address.';
            }
            if (kind == PHONE_INPUT && !isPhone(value)) {
                return 'Enter a valid phone number.';
            }
            if (kind == PROJECT_INPUT) {
                for (Option option : projects == null ? new List<Option>() : projects) {
                    if (option.value == value) {
                        return null;
                    }
                }
                return 'Choose a project from the list.';
            }
            return null;
        }

        // Puts the value in each of its fields; a problem if it does not suit one of them
        String write(Map<Schema.SObjectType, SObject> records, String value) {
            try {
                for (Target target : targets) {
                    target.write(records.get(target.objectType), value);
                }
                return null;
            } catch (Exception e) {
                return 'Enter a valid value.';
            }
        }

        void writeDefault(Map<Schema.SObjectType, SObject> records) {
            if (String.isNotBlank(record.Default_Value__c) && write(records, record.Default_Value__c.trim()) != null) {
                throw new SetupException(describe() + ': the Default Value ' + record.Default_Value__c + ' does not suit its fields.');
            }
        }
    }

    // An Account or Contact field that stores a value. A person's Name (which cannot be written itself) is split into
    // its first and last name fields.
    private class Target {
        final Schema.SObjectType objectType;
        Schema.DescribeFieldResult field;
        Schema.DescribeFieldResult firstName;
        Schema.DescribeFieldResult lastName;

        Target(Schema.SObjectType objectType, String apiName, String owner) {
            this.objectType = objectType;
            Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
            Schema.SObjectField token = fields.get(apiName);
            if (token == null) {
                throw new SetupException(owner + ': ' + objectType + ' has no field ' + apiName + '.');
            }
            Schema.DescribeFieldResult described = token.getDescribe();
            // Not isCreateable(): describe answers for the running user, and the site guest user may create nothing
            if (described.getType() != Schema.DisplayType.ID && !described.isCalculated() && canPut(objectType, described.getName())) {
                field = described;
            } else if (described.isNameField() && fields.containsKey('FirstName') && fields.containsKey('LastName')) {
                firstName = fields.get('FirstName').getDescribe();
                lastName = fields.get('LastName').getDescribe();
            } else {
                throw new SetupException(owner + ': ' + objectType + '.' + described.getName() + ' cannot be filled in.');
            }
        }

        // Whether a record can hold a value in this field at all, whoever is running (system fields cannot)
        Boolean canPut(Schema.SObjectType objectType, String apiName) {
            try {
                objectType.newSObject().put(apiName, null);
                return true;
            } catch (SObjectException e) {
                return false;
            }
        }

        Integer maxLength() {
            if (field == null) {
                return firstName.getLength() + 1 + lastName.getLength();
            }
            switch on field.getType() {
                when STRING, TEXTAREA, EMAIL, PHONE, URL, ENCRYPTEDSTRING {
                    return field.getLength();
                }
                when else {
                    return null;
                }
            }
        }

        void write(SObject record, String value) {
            if (field == null) {
                List<String> parts = splitName(value, firstName.getLength(), lastName.getLength());
                record.put(firstName.getName(), parts[0]);
                record.put(lastName.getName(), parts[1]);
            } else {
                record.put(field.getName(), valueFor(value));
            }
        }

        Object valueFor(String value) {
            switch on field.getType() {
                when BOOLEAN {
                    return Boolean.valueOf(value);
                }
                when INTEGER {
                    return Integer.valueOf(value);
                }
                when LONG {
                    return Long.valueOf(value);
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return Decimal.valueOf(value);
                }
                when DATE {
                    return Date.valueOf(value);
                }
                when DATETIME {
                    return Datetime.valueOf(value);
                }
                when REFERENCE {
                    return Id.valueOf(value);
                }
                when else {
                    return value;
                }
            }
        }
    }
}