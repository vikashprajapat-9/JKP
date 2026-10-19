// The SharePoint documents of contracts. A new contract gets one Document per category of the Contract Document Master
// (Partner Portal Setting; for example Contract Generated Document and Signed Document), each a SharePoint folder inside
// its account's folder, so the account folder holds all of the partner's documents:
//   <Account name>/<the account's own categories>, <Contract Generated Document>, <Signed Document>
// The account folder is made first when the account has none. The PDF of each generated draft of an agent contract
// (PartnerContractService) goes into the Contract Draft Category's folder as a Sub Document, and is not kept in
// Salesforce Files; a draft or signed copy still in Salesforce Files (contracts made before) is moved there too. The
// Documents component (sharePointDocumentManager) shows the folders on the contract and uploads the signed scan.
// Folders and uploads are callouts, so a queueable (Job) makes them after the save: callouts first, then the records.
public without sharing class ContractDocumentService {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_CONTRACT_DOCUMENTS_FAILED_SUBJECT = 'Contract documents not ready in SharePoint – {0}';
    @TestVisible private static final String PARTNER_CONTRACT_DOCUMENTS_FAILED_TEXT = 'The SharePoint folders or the draft PDF of contract {0} could not be created: {1}. The nightly Partner Exclusive Check tries again. The contract goes to the partner for signature only once its draft PDF is in its Contract Generated Document folder. If this continues, check the SharePoint connection.';


    // Contracts one job handles (each needs up to about a dozen callouts; a transaction may make 100)
    private static final Integer CONTRACTS_PER_JOB = 6;

    @TestVisible
    private static Partner_Portal_Setting__mdt setting {
        get {
            if (setting == null) {
                setting = Partner_Portal_Setting__mdt.getInstance('Default');
            }
            return setting;
        }
        set;
    }

    private static String settingText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    // =====================================================================================================
    // CONTRACT CREATED (ContractTrigger, after insert)
    // =====================================================================================================

    // The contracts' Documents, then their folders (and draft PDFs) in a job. In a batch step the batch starts the job
    // when it finishes (a batch step may start only one job, and PartnerExclusiveCheckBatch may need it).
    public static void afterInsert(List<Contract> contracts) {
        createDocuments(contracts);
        if (!System.isBatch()) {
            startJob(new Map<Id, Contract>(contracts).keySet());
        }
    }

    // One Document per category of the Contract Document Master for each contract without Documents, owned like the
    // contract (its CP Executive)
    public static List<Document__c> createDocuments(List<Contract> contracts) {
        List<Document__c> documents = new List<Document__c>();
        String masterName = settingText(setting == null ? null : setting.Contract_Document_Master__c);
        if (masterName == null || contracts.isEmpty()) {
            return documents;
        }
        List<Document_category__c> categories = [
            SELECT Name FROM Document_category__c WHERE Document_Master__r.Name = :masterName WITH SYSTEM_MODE ORDER BY CreatedDate, Name
        ];
        if (categories.isEmpty()) {
            return documents;
        }
        Set<Id> contractIds = new Map<Id, Contract>(contracts).keySet();
        Set<Id> withDocuments = new Set<Id>();
        for (Document__c existing : [SELECT Contract__c FROM Document__c WHERE Contract__c IN :contractIds WITH SYSTEM_MODE]) {
            withDocuments.add(existing.Contract__c);
        }
        for (Contract record : contracts) {
            if (withDocuments.contains(record.Id)) {
                continue;
            }
            for (Document_category__c category : categories) {
                documents.add(new Document__c(Name = category.Name, Contract__c = record.Id, OwnerId = record.OwnerId));
            }
        }
        for (Database.SaveResult result : Database.insert(documents, false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Contract Document not created: ' + result.getErrors());
            }
        }
        return documents;
    }

    // Starts the job for these contracts when this transaction may still start one; otherwise the nightly check's
    // sweep (pendingContractIds) takes them later
    public static void startJob(Set<Id> contractIds) {
        if (contractIds == null || contractIds.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new Job(new List<Id>(contractIds)));
        } else {
            System.debug(LoggingLevel.WARN, 'Contract documents left for the nightly check: ' + contractIds);
        }
    }

    // Contracts still waiting for a folder, for their draft PDF, or with a draft or signed copy still in Salesforce Files
    // (the nightly check's sweep)
    public static Set<Id> pendingContractIds() {
        Set<Id> contractIds = new Set<Id>();
        for (Document__c doc : [
            SELECT Contract__c FROM Document__c WHERE Contract__c != null AND Document_Id__c = null WITH SYSTEM_MODE LIMIT 200
        ]) {
            contractIds.add(doc.Contract__c);
        }
        for (Contract record : [
            SELECT Id FROM Contract
            WHERE Id IN (SELECT Contract__c FROM Document__c WHERE Contract__c != null)
              AND ((Draft_Version__c != null AND Contract_Stage__c != null AND Draft_Document_Id__c = null)
                OR Draft_Document_Id__c LIKE '069%' OR Signed_Document_Id__c LIKE '069%')
            WITH SYSTEM_MODE
            LIMIT 200
        ]) {
            contractIds.add(record.Id);
        }
        return contractIds;
    }

    // =====================================================================================================
    // THE JOB
    // =====================================================================================================

    public class Job implements Queueable, Database.AllowsCallouts {
        private final List<Id> contractIds;

        public Job(List<Id> contractIds) {
            this.contractIds = contractIds;
        }

        public void execute(QueueableContext context) {
            List<Id> now = new List<Id>();
            List<Id> later = new List<Id>();
            for (Id contractId : contractIds) {
                if (now.size() < CONTRACTS_PER_JOB) {
                    now.add(contractId);
                } else {
                    later.add(contractId);
                }
            }
            process(now);
            if (!later.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new Job(later));
            }
        }
    }

    // A file to upload for a contract: into its draft or signed folder, and the field that will name its Sub Document
    private class Upload {
        Id contractId;
        Id documentId;
        String folderId;
        String fileName;
        Blob data;
        Boolean signed;
        Sub_Document__c saved;
    }

    // For each contract: the account folder when the account has none, the Documents' folders, then the draft PDF and
    // any copy still in Salesforce Files; all callouts first, then the records. A contract that fails is logged and
    // left for the next run (the nightly check's sweep); the others go on.
    @TestVisible
    private static void process(List<Id> contractIds) {
        String draftCategory = settingText(setting == null ? null : setting.Contract_Draft_Category__c);
        String signedCategory = settingText(setting == null ? null : setting.Contract_Signed_Category__c);
        Map<Id, Contract> contracts = new Map<Id, Contract>([
            SELECT Id, ContractNumber, AccountId, Account.Name, Account.Document_Id__c, OwnerId, Draft_Version__c, Contract_Stage__c,
                CustomerSignedId, Draft_Document_Id__c, Signed_Document_Id__c,
                (SELECT Id, Name, Document_Id__c FROM Documents__r ORDER BY CreatedDate, Name)
            FROM Contract WHERE Id IN :contractIds WITH SYSTEM_MODE
        ]);
        Id templateId;
        Map<Id, String> accountFolders = new Map<Id, String>();
        Map<Id, String> documentFolders = new Map<Id, String>();
        List<Upload> uploads = new List<Upload>();
        Map<Id, String> failures = new Map<Id, String>();

        for (Contract record : contracts.values()) {
            try {
                if (record.AccountId == null || record.Documents__r.isEmpty()) {
                    continue;
                }
                Boolean needsFolders = false;
                for (Document__c doc : record.Documents__r) {
                    needsFolders |= String.isBlank(doc.Document_Id__c);
                }
                String accountFolder = String.isNotBlank(record.Account.Document_Id__c) ? record.Account.Document_Id__c
                    : accountFolders.get(record.AccountId);
                if (accountFolder == null && needsFolders) {
                    // The account's folder is saved on the account: an approved partner account is locked, so a user
                    // who may not edit it leaves this contract to the nightly check (run by an administrator) rather
                    // than leave a folder no account records
                    if (!mayEditAccount(record.AccountId)) {
                        System.debug(LoggingLevel.WARN, 'Contract ' + record.ContractNumber + ' waits for the nightly check: its account has no folder');
                        continue;
                    }
                    accountFolder = SharePointDocumentManagerController.createFolder(null, record.Account.Name);
                    accountFolders.put(record.AccountId, accountFolder);
                }
                Document__c draftDocument;
                Document__c signedDocument;
                Map<Id, String> folderByDocument = new Map<Id, String>();
                for (Document__c doc : record.Documents__r) {
                    String folder = doc.Document_Id__c;
                    if (String.isBlank(folder)) {
                        folder = SharePointDocumentManagerController.createFolder(accountFolder, doc.Name);
                        documentFolders.put(doc.Id, folder);
                    }
                    folderByDocument.put(doc.Id, folder);
                    if (draftCategory != null && doc.Name.equalsIgnoreCase(draftCategory) && draftDocument == null) {
                        draftDocument = doc;
                    }
                    if (signedCategory != null && doc.Name.equalsIgnoreCase(signedCategory) && signedDocument == null) {
                        signedDocument = doc;
                    }
                }

                // The draft: the generated PDF of the current version, or a draft still kept in Salesforce Files
                if (draftDocument != null) {
                    Upload draft;
                    if (isFilesId(record.Draft_Document_Id__c)) {
                        draft = fromFiles(record.Draft_Document_Id__c);
                    } else if (String.isBlank(record.Draft_Document_Id__c) && record.Draft_Version__c != null
                            && String.isNotBlank(record.Contract_Stage__c)) {
                        if (templateId == null) {
                            templateId = PartnerContractService.contractTemplateId();
                        }
                        PartnerContractService.DraftFile file = PartnerContractService.draftFile(record, templateId);
                        draft = new Upload();
                        draft.fileName = file.fileName;
                        draft.data = file.pdf;
                    }
                    if (draft != null) {
                        draft.signed = false;
                        uploads.add(send(draft, record.Id, draftDocument.Id, folderByDocument.get(draftDocument.Id)));
                    }
                }
                // A signed copy still kept in Salesforce Files
                if (signedDocument != null && isFilesId(record.Signed_Document_Id__c)) {
                    Upload signedCopy = fromFiles(record.Signed_Document_Id__c);
                    if (signedCopy != null) {
                        signedCopy.signed = true;
                        uploads.add(send(signedCopy, record.Id, signedDocument.Id, folderByDocument.get(signedDocument.Id)));
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Contract documents of ' + record.ContractNumber + ' not finished: ' + e.getMessage());
                failures.put(record.Id, e.getMessage());
            }
        }

        // The records
        List<Account> accounts = new List<Account>();
        for (Id accountId : accountFolders.keySet()) {
            accounts.add(new Account(Id = accountId, Document_Id__c = accountFolders.get(accountId)));
        }
        logFailures('Account folder not saved', Database.update(accounts, false, AccessLevel.SYSTEM_MODE));
        List<Document__c> documents = new List<Document__c>();
        for (Id documentId : documentFolders.keySet()) {
            documents.add(new Document__c(Id = documentId, Document_Id__c = documentFolders.get(documentId)));
        }
        logFailures('Contract Document folder not saved', Database.update(documents, false, AccessLevel.SYSTEM_MODE));
        List<Sub_Document__c> files = new List<Sub_Document__c>();
        for (Upload upload : uploads) {
            files.add(upload.saved);
        }
        logFailures('Contract file not saved', Database.insert(files, false, AccessLevel.SYSTEM_MODE));
        Map<Id, Contract> changes = new Map<Id, Contract>();
        for (Upload upload : uploads) {
            if (upload.saved.Id == null) {
                continue;
            }
            Contract change = changes.containsKey(upload.contractId) ? changes.get(upload.contractId) : new Contract(Id = upload.contractId);
            if (upload.signed) {
                change.Signed_Document_Id__c = upload.saved.Id;
            } else {
                change.Draft_Document_Id__c = upload.saved.Id;
            }
            changes.put(upload.contractId, change);
        }
        logFailures('Contract file not recorded', Database.update(changes.values(), false, AccessLevel.SYSTEM_MODE));

        // A verified draft waiting for its PDF goes to the partner now
        Set<Id> withDraft = new Set<Id>();
        for (Contract change : changes.values()) {
            if (String.isNotBlank(change.Draft_Document_Id__c)) {
                withDraft.add(change.Id);
            }
        }
        PartnerContractService.sendVerifiedForSignature(withDraft);
        tellOwners(failures, contracts);
    }

    // What could not be done is told to the contract's owner (the CP Executive) as a task, once while it is open; the
    // nightly check tries again
    private static void tellOwners(Map<Id, String> failures, Map<Id, Contract> contracts) {
        if (failures.isEmpty()) {
            return;
        }
        Set<String> open = new Set<String>();
        for (Task existing : [
            SELECT WhatId, Subject FROM Task WHERE WhatId IN :failures.keySet() AND IsClosed = false WITH SYSTEM_MODE
        ]) {
            open.add(String.valueOf(existing.WhatId) + existing.Subject);
        }
        List<Task> tasks = new List<Task>();
        for (Id contractId : failures.keySet()) {
            Contract record = contracts.get(contractId);
            String subject = String.format(PARTNER_CONTRACT_DOCUMENTS_FAILED_SUBJECT, new List<Object>{ record.ContractNumber }).left(255);
            if (open.contains(String.valueOf(contractId) + subject)) {
                continue;
            }
            tasks.add(new Task(
                WhatId = contractId,
                OwnerId = record.OwnerId,
                Subject = subject,
                Description = String.format(PARTNER_CONTRACT_DOCUMENTS_FAILED_TEXT, new List<Object>{
                    record.ContractNumber, String.valueOf(failures.get(contractId)).left(500)
                }),
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today().addDays(1)
            ));
        }
        logFailures('Contract documents task not created', Database.insert(tasks, false, AccessLevel.SYSTEM_MODE));
    }

    // Whether the running user may save the account: not when it is locked by its approval, unless they may modify all data
    private static Boolean mayEditAccount(Id accountId) {
        Boolean locked = false;
        try {
            locked = Approval.isLocked(accountId);
        } catch (Exception e) {
            locked = false;
        }
        return !locked || [SELECT PermissionsModifyAllData FROM Profile WHERE Id = :UserInfo.getProfileId() WITH SYSTEM_MODE].PermissionsModifyAllData;
    }

    // Uploads the file into the folder and gives it its public view link; the Sub Document is saved afterwards
    private static Upload send(Upload upload, Id contractId, Id documentId, String folderId) {
        upload.contractId = contractId;
        upload.documentId = documentId;
        upload.folderId = folderId;
        String itemId = SharePointDocumentManagerController.uploadBase64(folderId, upload.fileName, EncodingUtil.base64Encode(upload.data), false);
        SharePointDocumentManagerController.UploadResult link = SharePointDocumentManagerController.linkFile(folderId, itemId);
        upload.saved = new Sub_Document__c(
            Name = (String.isNotBlank(link.storedName) ? link.storedName : upload.fileName).left(80),
            Document__c = documentId,
            File_URL__c = link.fileUrl,
            Public_Link__c = link.isPublic == true
        );
        upload.data = null;
        return upload;
    }

    // The latest version of a Salesforce File (a contract made before its documents were kept in SharePoint)
    private static Upload fromFiles(String documentId) {
        List<ContentVersion> versions = [
            SELECT Title, FileExtension, VersionData FROM ContentVersion
            WHERE ContentDocumentId = :Id.valueOf(documentId) AND IsLatest = true
            WITH SYSTEM_MODE LIMIT 1
        ];
        if (versions.isEmpty()) {
            return null;
        }
        Upload upload = new Upload();
        String extension = String.isBlank(versions[0].FileExtension) ? '' : '.' + versions[0].FileExtension;
        upload.fileName = versions[0].Title.toLowerCase().endsWith(extension.toLowerCase()) ? versions[0].Title : versions[0].Title + extension;
        upload.data = versions[0].VersionData;
        return upload;
    }

    // Whether the value names a Salesforce File (ContentDocument) rather than a Sub Document
    @TestVisible
    private static Boolean isFilesId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            return Id.valueOf(value.trim()).getSObjectType() == ContentDocument.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }

    private static void logFailures(String what, List<Database.SaveResult> results) {
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, what + ': ' + result.getErrors());
            }
        }
    }
}