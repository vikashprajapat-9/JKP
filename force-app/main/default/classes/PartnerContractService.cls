// The exclusive agent contract of a channel partner (master agent), the onboarding chart's "Condition met in 30 days?
// Yes" branch. The Contract's Contract Stage follows it:
//  1. Draft: the nightly check (PartnerExclusiveCheckBatch) generates the contract with a PDF made from the Contract
//     Template of the Partner Portal Setting (stored in SharePoint, in the contract's Contract Generated Document folder,
//     by ContractDocumentService), and verification and approval tasks for the CP Manager (the partner account owner's
//     manager) and the Head of Sales. Once both have closed their task (in any order; only the CP
//     Manager's when no Head of Sales is set up), the contract is
//  2. Sent for Signature: the partner gets an email, downloads the contract on the portal (My Contract) and signs it
//     offline. The CP Executive (the contract's owner) then records
//  3. Signed (with the date): the partner becomes Exclusive and the CP Executive gets a task to upload the signed scan;
//     or Not Signed (with the reason): a new draft is generated and goes to verification again;
//  4. Completed: the signed scan is in the contract's Signed Document folder (Documents) and its start and end dates
//     are entered; the contract is Activated.
// Making the partner Exclusive and activating the contract need an administrator (approved partner accounts stay locked
// for other users, and only some profiles may activate contracts): the CP Executive's change publishes a Partner
// Contract Change event, which PartnerContractChangeTrigger applies as the user of its subscriber configuration.
// Texts are custom labels (Partner_Contract_*); the templates, term and people are in the Partner Portal Setting.
public without sharing class PartnerContractService {
    // Messages this class shows or sends
    @TestVisible private static final String PARTNER_CONTRACT_DRAFT_FILE_TITLE = 'Agent Contract - {0} - Draft {1}';
    @TestVisible private static final String PARTNER_CONTRACT_HEAD_OF_SALES_TEXT = 'The CP Manager verifies this draft too: the contract goes to the partner once you have both closed your tasks.';
    @TestVisible private static final String PARTNER_CONTRACT_NOT_SIGNED_TEXT = 'The partner did not sign the previous draft: {0}';
    @TestVisible private static final String PARTNER_CONTRACT_SIGNED_COPY_NEEDED = 'Upload the signed and scanned contract to the Signed Document folder of this contract (Documents) before setting it to Completed.';
    @TestVisible private static final String PARTNER_CONTRACT_STAGE_ORDER = 'This contract cannot move from {0} to {1}. After Sent for Signature it becomes Signed or Not Signed, and a Signed contract becomes Completed.';
    @TestVisible private static final String PARTNER_CONTRACT_UPLOAD_SUBJECT = 'Upload the signed agent contract – {0}';
    @TestVisible private static final String PARTNER_CONTRACT_UPLOAD_TEXT = '{0} signed the agent contract on {1}. Upload the signed and scanned copy to the Signed Document folder of contract {2} (Documents), enter the Contract Start Date and Contract End Date, and set the Contract Stage to Completed.';
    @TestVisible private static final String PARTNER_CONTRACT_VERIFICATION_SUBJECT = 'Verify and approve the agent contract – {0}';
    @TestVisible private static final String PARTNER_CONTRACT_VERIFICATION_TEXT = 'Draft {1} of the exclusive agent contract of {0} ({2}) is in the Contract Generated Document folder of the contract (Documents). Verify it, and close this task when it is approved. The contract goes to the partner for signature on the Partner Portal once every verification task of this draft is closed.';


    public static final String DRAFT = 'Draft';
    public static final String SENT = 'Sent for Signature';
    public static final String SIGNED = 'Signed';
    public static final String NOT_SIGNED = 'Not Signed';
    public static final String COMPLETED = 'Completed';

    // The standard Contract Status for each step
    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_IN_APPROVAL = 'In Approval Process';
    private static final String STATUS_ACTIVATED = 'Activated';

    // The stages the CP Executive may move a contract to, from each stage
    private static final Map<String, Set<String>> NEXT_STAGES = new Map<String, Set<String>>{
        SENT => new Set<String>{ SIGNED, NOT_SIGNED },
        SIGNED => new Set<String>{ COMPLETED }
    };

    // Set while this class moves contracts itself (a new draft, sending for signature)
    private static Boolean movingContracts = false;

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

    public class ContractException extends Exception {}

    // =====================================================================================================
    // 1. DRAFT
    // =====================================================================================================

    // A first contract draft for each of these partners that has no contract yet; returns the new contracts
    public static List<Contract> createDrafts(List<Account> partners) {
        Set<Id> accountIds = new Map<Id, Account>(partners).keySet();
        Set<Id> withContract = new Set<Id>();
        for (Contract existing : [SELECT AccountId FROM Contract WHERE AccountId IN :accountIds WITH SYSTEM_MODE]) {
            withContract.add(existing.AccountId);
        }
        Map<Id, Account> accounts = new Map<Id, Account>([
            SELECT Id, Name, OwnerId FROM Account WHERE Id IN :accountIds AND Id NOT IN :withContract WITH SYSTEM_MODE
        ]);
        if (accounts.isEmpty()) {
            return new List<Contract>();
        }
        Map<Id, Id> contactByAccount = primaryContacts(accounts.keySet());
        Id executive = activeUserNamed(setting == null ? null : setting.CP_Executive_Username__c);
        Integer term = setting == null || setting.Contract_Term_Months__c == null ? null : setting.Contract_Term_Months__c.intValue();
        List<Contract> contracts = new List<Contract>();
        for (Account partner : accounts.values()) {
            contracts.add(new Contract(
                AccountId = partner.Id,
                OwnerId = executive != null ? executive : partner.OwnerId,
                Status = STATUS_DRAFT,
                Contract_Stage__c = DRAFT,
                Draft_Version__c = 1,
                StartDate = Date.today(),
                ContractTerm = term,
                CustomerSignedId = contactByAccount.get(partner.Id)
            ));
        }
        Database.insert(contracts, AccessLevel.SYSTEM_MODE);
        prepareForVerification(contracts, new Map<Id, String>());
        return contracts;
    }

    // The draft PDF of each contract and its verification tasks; reasons: why the partner did not sign the last draft
    private static void prepareForVerification(List<Contract> contracts, Map<Id, String> reasons) {
        Map<Id, Contract> current = new Map<Id, Contract>([
            SELECT Id, ContractNumber, AccountId, Account.Name, Account.OwnerId, OwnerId, Draft_Version__c, CustomerSignedId
            FROM Contract WHERE Id IN :new Map<Id, Contract>(contracts).keySet() WITH SYSTEM_MODE
        ]);
        contractTemplateId();
        Map<Id, Id> managerByOwner = activeManagersOf(current.values());
        Id headOfSales = activeUserNamed(setting == null ? null : setting.Head_Of_Sales_Username__c);

        List<Task> tasks = new List<Task>();
        List<Contract> withTasks = new List<Contract>();
        for (Contract record : current.values()) {
            String draftText = String.format(PARTNER_CONTRACT_VERIFICATION_TEXT, new List<Object>{
                record.Account.Name, String.valueOf(record.Draft_Version__c == null ? 1 : record.Draft_Version__c.intValue()), record.ContractNumber
            });
            if (String.isNotBlank(reasons.get(record.Id))) {
                draftText += '\n\n' + String.format(PARTNER_CONTRACT_NOT_SIGNED_TEXT, new List<Object>{ reasons.get(record.Id) });
            }
            Id manager = managerByOwner.get(record.Account.OwnerId);
            tasks.add(verificationTask(record, manager != null ? manager : record.Account.OwnerId, draftText));
            if (headOfSales != null) {
                tasks.add(verificationTask(record, headOfSales, draftText + '\n\n' + PARTNER_CONTRACT_HEAD_OF_SALES_TEXT));
            }
            withTasks.add(record);
        }
        Database.insert(tasks, AccessLevel.SYSTEM_MODE);

        List<Contract> updates = new List<Contract>();
        Integer next = 0;
        for (Contract record : withTasks) {
            Contract change = new Contract(Id = record.Id);
            change.Verification_Task_Id__c = tasks[next++].Id;
            change.Head_Of_Sales_Task_Id__c = headOfSales != null ? tasks[next++].Id : null;
            updates.add(change);
        }
        move(updates);
    }

    private static Task verificationTask(Contract record, Id ownerId, String description) {
        return new Task(
            WhatId = record.Id,
            OwnerId = ownerId,
            Subject = String.format(PARTNER_CONTRACT_VERIFICATION_SUBJECT, new List<Object>{ record.Account.Name }),
            Description = description,
            Status = 'Not Started',
            Priority = 'High',
            ActivityDate = Date.today().addDays(2)
        );
    }

    // The PDF of a contract's current draft, made from the Contract Template: ContractDocumentService uploads it to the
    // contract's Contract Generated Document folder in SharePoint (it is not kept in Salesforce Files). The contract needs
    // Id, Account.Name, Draft_Version__c and CustomerSignedId.
    public class DraftFile {
        public String fileName;
        public Blob pdf;
    }

    public static DraftFile draftFile(Contract record, Id templateId) {
        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templateId, record.CustomerSignedId, record.Id);
        String html = String.isNotBlank(rendered.getHtmlBody()) ? rendered.getHtmlBody()
            : '<p>' + String.valueOf(rendered.getPlainTextBody()).escapeHtml4().replace('\n', '<br/>') + '</p>';
        DraftFile file = new DraftFile();
        file.fileName = String.format(PARTNER_CONTRACT_DRAFT_FILE_TITLE, new List<Object>{
            record.Account.Name, String.valueOf(record.Draft_Version__c == null ? 1 : record.Draft_Version__c.intValue())
        }) + '.pdf';
        file.pdf = Blob.toPdf(html);
        return file;
    }

    // The Contract Template of the Partner Portal Setting; a draft cannot be made without it
    public static Id contractTemplateId() {
        String templateName = setting == null ? null : setting.Contract_Template__c;
        List<EmailTemplate> templates = String.isBlank(templateName) ? new List<EmailTemplate>()
            : [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName.trim() WITH SYSTEM_MODE LIMIT 1];
        if (templates.isEmpty()) {
            throw new ContractException('The Contract Template of the Partner Portal Setting is missing: ' + templateName);
        }
        return templates[0].Id;
    }

    // =====================================================================================================
    // 2. VERIFIED: SENT FOR SIGNATURE (PartnerContractTaskTrigger)
    // =====================================================================================================

    // A verification task of a draft was closed: once the CP Manager's and the Head of Sales' tasks are both closed (in
    // any order), the contract is Sent for Signature and the partner is told it is on the portal
    public static void verificationTasksClosed(List<Task> tasks, Map<Id, Task> oldTasks) {
        Set<String> closedIds = new Set<String>();
        for (Task record : tasks) {
            Task before = oldTasks == null ? null : oldTasks.get(record.Id);
            if (record.Status == 'Completed' && (before == null || before.Status != 'Completed') && record.WhatId != null
                    && record.WhatId.getSObjectType() == Contract.SObjectType) {
                closedIds.add(record.Id);
            }
        }
        if (closedIds.isEmpty()) {
            return;
        }
        List<Contract> drafts = [
            SELECT Id, CustomerSignedId, Verification_Task_Id__c, Head_Of_Sales_Task_Id__c, Draft_Document_Id__c FROM Contract
            WHERE (Verification_Task_Id__c IN :closedIds OR Head_Of_Sales_Task_Id__c IN :closedIds) AND Contract_Stage__c = :DRAFT
            WITH SYSTEM_MODE
        ];
        sendWhenReady(drafts);
    }

    // Draft contracts whose draft PDF has just been saved (ContractDocumentService): sent for signature when their
    // verification tasks are already closed
    public static void sendVerifiedForSignature(Set<Id> contractIds) {
        if (contractIds == null || contractIds.isEmpty()) {
            return;
        }
        sendWhenReady([
            SELECT Id, CustomerSignedId, Verification_Task_Id__c, Head_Of_Sales_Task_Id__c, Draft_Document_Id__c FROM Contract
            WHERE Id IN :contractIds AND Contract_Stage__c = :DRAFT AND Verification_Task_Id__c != null
            WITH SYSTEM_MODE
        ]);
    }

    // A draft contract goes to Sent for Signature once its verification tasks are all closed and its draft PDF is in
    // SharePoint (Draft_Document_Id__c). Without the PDF it waits in Draft: the PDF job is started again, and sends it as
    // soon as the PDF is saved.
    private static void sendWhenReady(List<Contract> drafts) {
        if (drafts.isEmpty()) {
            return;
        }
        Set<String> taskIds = new Set<String>();
        for (Contract record : drafts) {
            taskIds.add(record.Verification_Task_Id__c);
            taskIds.add(record.Head_Of_Sales_Task_Id__c);
        }
        Set<String> completedIds = new Set<String>();
        for (Task record : [SELECT Id FROM Task WHERE Id IN :taskIds AND Status = 'Completed' WITH SYSTEM_MODE]) {
            completedIds.add(record.Id);
        }
        List<Contract> verified = new List<Contract>();
        List<Contract> forSignature = new List<Contract>();
        Set<Id> waitingForPdf = new Set<Id>();
        for (Contract record : drafts) {
            Boolean managerDone = completedIds.contains(record.Verification_Task_Id__c);
            Boolean headOfSalesDone = String.isBlank(record.Head_Of_Sales_Task_Id__c) || completedIds.contains(record.Head_Of_Sales_Task_Id__c);
            if (managerDone && headOfSalesDone) {
                if (String.isBlank(record.Draft_Document_Id__c)) {
                    waitingForPdf.add(record.Id);
                    continue;
                }
                verified.add(record);
                forSignature.add(new Contract(Id = record.Id, Contract_Stage__c = SENT, Status = STATUS_IN_APPROVAL));
            }
        }
        if (!waitingForPdf.isEmpty()) {
            ContractDocumentService.startJob(waitingForPdf);
        }
        if (verified.isEmpty()) {
            return;
        }
        move(forSignature);
        emailPartners(verified);
    }

    // The Contract Ready email to each contract's partner contact
    private static void emailPartners(List<Contract> contracts) {
        String templateName = setting == null ? null : setting.Contract_Ready_Email_Template__c;
        if (String.isBlank(templateName)) {
            return;
        }
        List<EmailTemplate> templates = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :templateName.trim() WITH SYSTEM_MODE LIMIT 1];
        if (templates.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Contract Ready Email Template not found: ' + templateName);
            return;
        }
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Contract record : contracts) {
            if (record.CustomerSignedId == null) {
                continue;
            }
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTemplateId(templates[0].Id);
            email.setTargetObjectId(record.CustomerSignedId);
            email.setWhatId(record.Id);
            email.setSaveAsActivity(false);
            emails.add(email);
        }
        if (emails.isEmpty()) {
            return;
        }
        for (Messaging.SendEmailResult result : PartnerEmailSender.send(emails)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Contract Ready email not sent: ' + result.getErrors());
            }
        }
    }

    // =====================================================================================================
    // 3 AND 4. SIGNED, NOT SIGNED, COMPLETED (ContractTrigger)
    // =====================================================================================================

    // The CP Executive's steps: in order (Sent for Signature → Signed or Not Signed; Signed → Completed); Completed needs
    // the signed scan on the contract, which becomes the Signed Document, and activates the contract
    public static void beforeUpdate(List<Contract> contracts, Map<Id, Contract> oldContracts) {
        if (movingContracts) {
            return;
        }
        List<Contract> completing = new List<Contract>();
        for (Contract record : contracts) {
            String fromStage = oldContracts.get(record.Id).Contract_Stage__c;
            String toStage = record.Contract_Stage__c;
            if (toStage == fromStage) {
                continue;
            }
            Set<String> allowed = NEXT_STAGES.get(fromStage);
            if (allowed == null || !allowed.contains(toStage)) {
                record.Contract_Stage__c.addError(String.format(PARTNER_CONTRACT_STAGE_ORDER, new List<Object>{ fromStage, toStage }));
                continue;
            }
            if (toStage == SIGNED) {
                record.CustomerSignedDate = record.Signed_On__c;
            } else if (toStage == COMPLETED) {
                completing.add(record);
            }
        }
        if (completing.isEmpty()) {
            return;
        }
        Map<Id, Id> signedByContract = signedScans(completing);
        for (Contract record : completing) {
            Id scan = signedByContract.get(record.Id);
            if (scan == null) {
                record.addError(PARTNER_CONTRACT_SIGNED_COPY_NEEDED);
                continue;
            }
            record.Signed_Document_Id__c = scan;
            record.StartDate = record.Contract_Start__c;
        }
    }

    // Signed: the partner becomes Exclusive and the CP Executive gets the upload task. Completed: the contract is
    // activated. Not Signed: a new draft goes to verification again.
    public static void afterUpdate(List<Contract> contracts, Map<Id, Contract> oldContracts) {
        if (movingContracts) {
            return;
        }
        List<Contract> signedContracts = new List<Contract>();
        List<Contract> notSignedContracts = new List<Contract>();
        List<Partner_Contract_Change__e> changes = new List<Partner_Contract_Change__e>();
        for (Contract record : contracts) {
            String fromStage = oldContracts.get(record.Id).Contract_Stage__c;
            if (record.Contract_Stage__c == fromStage) {
                continue;
            }
            if (record.Contract_Stage__c == SIGNED) {
                signedContracts.add(record);
                changes.add(new Partner_Contract_Change__e(Contract_Id__c = record.Id, Change__c = SIGNED));
            } else if (record.Contract_Stage__c == COMPLETED) {
                changes.add(new Partner_Contract_Change__e(Contract_Id__c = record.Id, Change__c = COMPLETED));
            } else if (record.Contract_Stage__c == NOT_SIGNED) {
                notSignedContracts.add(record);
            }
        }
        if (!changes.isEmpty()) {
            for (Database.SaveResult result : EventBus.publish(changes)) {
                if (!result.isSuccess()) {
                    throw new ContractException('The contract step could not be passed on: ' + result.getErrors());
                }
            }
        }
        if (!signedContracts.isEmpty()) {
            createUploadTasks(signedContracts);
        }
        if (!notSignedContracts.isEmpty()) {
            redraft(notSignedContracts);
        }
    }

    // The newest file in each contract's Signed Document folder (the Contract Signed Category of the Partner Portal
    // Setting): the signed and scanned contract, as its Sub Document
    private static Map<Id, Id> signedScans(List<Contract> contracts) {
        Map<Id, Id> scanByContract = new Map<Id, Id>();
        String category = setting == null ? null : setting.Contract_Signed_Category__c;
        if (String.isBlank(category)) {
            return scanByContract;
        }
        for (Sub_Document__c file : [
            SELECT Id, Document__r.Contract__c FROM Sub_Document__c
            WHERE Document__r.Contract__c IN :new Map<Id, Contract>(contracts).keySet() AND Document__r.Name = :category.trim()
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC, Id DESC
        ]) {
            if (!scanByContract.containsKey(file.Document__r.Contract__c)) {
                scanByContract.put(file.Document__r.Contract__c, file.Id);
            }
        }
        return scanByContract;
    }

    // The Partner Contract Change events, as an administrator: Signed makes the partner Exclusive ("Master Agent confirmed
    // to Exclusive"); Completed activates the contract. Should an update still fail, the nightly check makes a partner
    // with a signed contract Exclusive.
    public static void applyChanges(List<Partner_Contract_Change__e> changes) {
        Set<Id> signedIds = new Set<Id>();
        Set<Id> completedIds = new Set<Id>();
        for (Partner_Contract_Change__e change : changes) {
            if (String.isBlank(change.Contract_Id__c)) {
                continue;
            }
            if (change.Change__c == SIGNED) {
                signedIds.add(change.Contract_Id__c);
            } else if (change.Change__c == COMPLETED) {
                completedIds.add(change.Contract_Id__c);
            }
        }
        Map<Id, Account> exclusive = new Map<Id, Account>();
        List<Contract> activated = new List<Contract>();
        for (Contract record : [
            SELECT Id, AccountId, Contract_Stage__c, Status FROM Contract WHERE Id IN :signedIds OR Id IN :completedIds WITH SYSTEM_MODE
        ]) {
            if (signedIds.contains(record.Id) || completedIds.contains(record.Id)) {
                exclusive.put(record.AccountId, new Account(Id = record.AccountId, Partner_Type__c = PartnerTemporaryAccess.EXCLUSIVE));
            }
            if (completedIds.contains(record.Id) && record.Contract_Stage__c == COMPLETED && record.Status != STATUS_ACTIVATED) {
                activated.add(new Contract(Id = record.Id, Status = STATUS_ACTIVATED));
            }
        }
        for (Database.SaveResult result : Database.update(exclusive.values(), false, AccessLevel.SYSTEM_MODE)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Partner not made Exclusive (the nightly check retries): ' + result.getErrors());
            }
        }
        Boolean wasMoving = movingContracts;
        movingContracts = true;
        try {
            for (Database.SaveResult result : Database.update(activated, false, AccessLevel.SYSTEM_MODE)) {
                if (!result.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'Contract not activated: ' + result.getErrors());
                }
            }
        } finally {
            movingContracts = wasMoving;
        }
    }

    // The CP Executive's task to upload the signed scan and enter the contract dates
    private static void createUploadTasks(List<Contract> contracts) {
        List<Task> tasks = new List<Task>();
        for (Contract record : [
            SELECT Id, OwnerId, ContractNumber, Account.Name, Signed_On__c FROM Contract
            WHERE Id IN :new Map<Id, Contract>(contracts).keySet() WITH SYSTEM_MODE
        ]) {
            tasks.add(new Task(
                WhatId = record.Id,
                OwnerId = record.OwnerId,
                Subject = String.format(PARTNER_CONTRACT_UPLOAD_SUBJECT, new List<Object>{ record.Account.Name }),
                Description = String.format(PARTNER_CONTRACT_UPLOAD_TEXT, new List<Object>{
                    record.Account.Name, record.Signed_On__c == null ? '' : record.Signed_On__c.format(), record.ContractNumber
                }),
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = Date.today().addDays(3)
            ));
        }
        Database.insert(tasks, AccessLevel.SYSTEM_MODE);
    }

    // "Signed by CP? No": the next version of the draft, back to verification with the reason
    private static void redraft(List<Contract> contracts) {
        Map<Id, String> reasons = new Map<Id, String>();
        List<Contract> drafts = new List<Contract>();
        for (Contract record : contracts) {
            reasons.put(record.Id, record.Not_Signed_Reason__c);
            drafts.add(new Contract(
                Id = record.Id,
                Contract_Stage__c = DRAFT,
                Status = STATUS_DRAFT,
                Draft_Version__c = (record.Draft_Version__c == null ? 1 : record.Draft_Version__c) + 1,
                Signed_On__c = null,
                Draft_Document_Id__c = null
            ));
        }
        move(drafts);
        prepareForVerification(drafts, reasons);
        // The new draft's PDF goes to the contract's Contract Generated Document folder
        ContractDocumentService.startJob(new Map<Id, Contract>(drafts).keySet());
    }

    // =====================================================================================================
    // HELPERS
    // =====================================================================================================

    // Contract updates of this class, which skip the CP Executive's stage rules
    private static void move(List<Contract> contracts) {
        if (contracts.isEmpty()) {
            return;
        }
        Boolean wasMoving = movingContracts;
        movingContracts = true;
        try {
            Database.update(contracts, AccessLevel.SYSTEM_MODE);
        } finally {
            movingContracts = wasMoving;
        }
    }

    // The first contact of each account (the partner who signs)
    private static Map<Id, Id> primaryContacts(Set<Id> accountIds) {
        Map<Id, Id> contactByAccount = new Map<Id, Id>();
        for (Contact person : [
            SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds WITH SYSTEM_MODE ORDER BY CreatedDate ASC, Id ASC
        ]) {
            if (!contactByAccount.containsKey(person.AccountId)) {
                contactByAccount.put(person.AccountId, person.Id);
            }
        }
        return contactByAccount;
    }

    // By account owner, their manager when the manager is an active user (the CP Manager)
    private static Map<Id, Id> activeManagersOf(List<Contract> contracts) {
        Set<Id> ownerIds = new Set<Id>();
        for (Contract record : contracts) {
            ownerIds.add(record.Account.OwnerId);
        }
        Map<Id, Id> managers = new Map<Id, Id>();
        for (User owner : [
            SELECT Id, ManagerId FROM User WHERE Id IN :ownerIds AND ManagerId != null AND Manager.IsActive = true WITH SYSTEM_MODE
        ]) {
            managers.put(owner.Id, owner.ManagerId);
        }
        return managers;
    }

    private static Id activeUserNamed(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        List<User> users = [SELECT Id FROM User WHERE Username = :username.trim() AND IsActive = true WITH SYSTEM_MODE LIMIT 1];
        return users.isEmpty() ? null : users[0].Id;
    }
}