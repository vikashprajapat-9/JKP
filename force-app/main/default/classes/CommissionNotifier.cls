// Tells people about what happens in Commission Setup: a bell notification that opens the Commission Setup tab,
// and a plain email as well when the Commission Setting switches emails on.
// The work runs in a Queueable so that it is never part of the approval transaction, and nothing in this class
// lets an error out: a notification that cannot be sent must not stop a submission, an approval or a target change.
public without sharing class CommissionNotifier implements Queueable {

    public static final String SUBMITTED = 'SUBMITTED';
    public static final String APPROVED = 'APPROVED';
    public static final String REJECTED = 'REJECTED';
    public static final String WITHDRAWN = 'WITHDRAWN';
    public static final String TARGET_CHANGED = 'TARGET_CHANGED';

    // The tab the notification opens and the views of the commissionSetup component
    private static final String TAB_NAME = 'Commission_Setup';
    private static final String VIEW_OVERVIEW = 'overview';
    private static final String VIEW_REVIEW = 'review';
    private static final String VIEW_TARGETS = 'targets';
    private static final String VIEW_TERMS = 'terms';
    // Platform limits of a custom notification
    private static final Integer MAX_RECIPIENTS = 500;
    private static final Integer TITLE_LENGTH = 250;
    private static final Integer BODY_LENGTH = 750;
    private static final String RULE_NONE = 'None';
    private static final String RATE_FLAT = 'Flat';

    private final String eventName;
    private final Set<Id> recordIds;
    // Who did it: a queued job still runs as that user, but the name is kept so that the text never depends on it
    private final String actorName;
    // Only for a target change made on the Targets screen: "10 → 12" per target row, the day and the reason
    private Map<Id, String> changeTexts;
    private Date effectiveFrom;
    private String reason;

    // What a test can look at: every notification that was handed over for sending
    @TestVisible
    private class Sent {
        public Set<Id> userIds;
        public String title;
        public String body;
        public Id configId;
        public String view;
    }
    @TestVisible
    private static List<Sent> sentLog = new List<Sent>();
    @TestVisible
    private static Integer emailsPrepared = 0;

    // Looked up once per transaction
    private static Boolean typeResolved = false;
    private static Id typeId;

    @TestVisible
    private CommissionNotifier(String eventName, Set<Id> recordIds) {
        this.eventName = eventName;
        this.recordIds = recordIds;
        this.actorName = UserInfo.getName();
    }

    // SUBMITTED | APPROVED | REJECTED | WITHDRAWN with configuration ids, TARGET_CHANGED with target ids. Never throws.
    public static void enqueue(String eventName, Set<Id> recordIds) {
        try {
            if (String.isBlank(eventName) || recordIds == null || recordIds.isEmpty()) {
                return;
            }
            start(new CommissionNotifier(eventName.trim().toUpperCase(), recordIds.clone()));
        } catch (Exception problem) {
            note('enqueue ' + eventName, problem);
        }
    }

    // A target change with what changed for each row ("10 → 12"), the day it applies from and the reason. Never throws.
    public static void enqueueTargets(Map<Id, String> changeByTargetId, Date effectiveFrom, String reason) {
        try {
            if (changeByTargetId == null || changeByTargetId.isEmpty()) {
                return;
            }
            CommissionNotifier job = new CommissionNotifier(TARGET_CHANGED, changeByTargetId.keySet().clone());
            job.changeTexts = changeByTargetId.clone();
            job.effectiveFrom = effectiveFrom;
            job.reason = reason;
            start(job);
        } catch (Exception problem) {
            note('enqueue ' + TARGET_CHANGED, problem);
        }
    }

    // In a test, and when the transaction cannot queue another job, the notifications are sent straight away
    private static void start(CommissionNotifier job) {
        if (Test.isRunningTest() || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            job.run();
        } else {
            System.enqueueJob(job);
        }
    }

    public void execute(QueueableContext context) {
        run();
    }

    private void run() {
        try {
            if (eventName == TARGET_CHANGED) {
                targetChanged();
                return;
            }
            if (eventName != SUBMITTED && eventName != APPROVED && eventName != REJECTED && eventName != WITHDRAWN) {
                return;
            }
            List<Commission_Config__c> configs = [
                SELECT Id, Name, Reference__c, Version__c, Project__c, Project__r.Name, Start_Date__c, End_Date__c,
                    Approver__c, Submitted_By__c, Submitted_By__r.Name, Approved_By__r.Name, Decision_By__r.Name,
                    Decision_Comments__c
                FROM Commission_Config__c
                WHERE Id IN :recordIds
                WITH SYSTEM_MODE
                ORDER BY Name
            ];
            for (Commission_Config__c config : configs) {
                try {
                    configEvent(config);
                } catch (Exception problem) {
                    note(eventName + ' ' + config.Name, problem);
                }
            }
            if (eventName == APPROVED) {
                payees(configs);
            }
        } catch (Exception problem) {
            note(eventName, problem);
        }
    }

    // ------------------------------------------------------------ configuration events

    private void configEvent(Commission_Config__c config) {
        String projectName = config.Project__r == null ? '' : config.Project__r.Name;
        String versionText = CommissionTargetService.formatNumber(config.Version__c);
        String period = CommissionTargetService.periodText(config.Start_Date__c, config.End_Date__c);

        if (eventName == SUBMITTED) {
            // To the approver Finance chose
            deliver(new Set<Id>{ config.Approver__c }, Label.Commission_Notify_Submitted_Title,
                CommissionTargetService.fill(Label.Commission_Notify_Submitted_Body, new List<Object>{
                    nameOf(config.Submitted_By__r), config.Name, versionText, projectName, period
                }), config.Id, VIEW_REVIEW);
        } else if (eventName == APPROVED) {
            // To whoever submitted it, Finance and the people who watch the configurations
            Set<Id> audience = idsOf(CommissionAccess.usersWho(CommissionAccess.CONFIGURE));
            audience.addAll(idsOf(CommissionAccess.usersWho(CommissionAccess.ALERT)));
            audience.add(config.Submitted_By__c);
            deliver(audience, Label.Commission_Notify_Approved_Title,
                CommissionTargetService.fill(Label.Commission_Notify_Approved_Body, new List<Object>{
                    nameOf(config.Approved_By__r), config.Name, versionText, projectName, period
                }), config.Id, VIEW_REVIEW);
        } else if (eventName == REJECTED) {
            // To all of Finance, not only the submitter, with the approver's comment
            String comment = String.isBlank(config.Decision_Comments__c) ? Label.Commission_Notify_No_Comment : config.Decision_Comments__c;
            deliver(idsOf(CommissionAccess.usersWho(CommissionAccess.CONFIGURE)), Label.Commission_Notify_Rejected_Title,
                CommissionTargetService.fill(Label.Commission_Notify_Rejected_Body, new List<Object>{
                    nameOf(config.Decision_By__r), config.Name, versionText, projectName, comment
                }), config.Id, VIEW_REVIEW);
        } else if (eventName == WITHDRAWN) {
            // To the approver who had it in their list
            deliver(new Set<Id>{ config.Approver__c }, Label.Commission_Notify_Withdrawn_Title,
                CommissionTargetService.fill(Label.Commission_Notify_Withdrawn_Body, new List<Object>{
                    nameOf(config.Decision_By__r), config.Name, versionText, projectName
                }), config.Id, VIEW_REVIEW);
        }
    }

    // After an approval everybody who holds a paid designation is told their own target and rates
    private void payees(List<Commission_Config__c> configs) {
        try {
            Map<Id, Commission_Config__c> configById = new Map<Id, Commission_Config__c>(configs);
            Map<String, CommissionDto.Designation> catalog = new Map<String, CommissionDto.Designation>();
            for (CommissionDto.Designation designation : CommissionCatalog.designations()) {
                if (String.isNotBlank(designation.key)) {
                    catalog.put(designation.key.toLowerCase(), designation);
                }
            }
            // The paid designations of each configuration, by the roles that hold them
            Map<String, List<Commission_Rate__c>> ratesByRole = new Map<String, List<Commission_Rate__c>>();
            Set<String> references = new Set<String>();
            for (Commission_Rate__c rate : [
                SELECT Id, Config__c, Designation__c, Designation_Label__c, Rate_Type__c, Current_Rate__c, Exceed_Rate__c,
                    Flat_Amount__c, Target__c, Target_Basis__c, Target_Rule__c
                FROM Commission_Rate__c
                WHERE Config__c IN :configById.keySet() AND Active__c = true AND Designation__c != null
                WITH SYSTEM_MODE
                ORDER BY Config__c, Name
            ]) {
                CommissionDto.Designation designation = catalog.get(rate.Designation__c.toLowerCase());
                for (String role : CommissionTargetService.rolesOf(designation)) {
                    if (!ratesByRole.containsKey(role)) {
                        ratesByRole.put(role, new List<Commission_Rate__c>());
                    }
                    ratesByRole.get(role).add(rate);
                }
                references.add(CommissionTargetService.referenceOf(configById.get(rate.Config__c)));
            }
            if (ratesByRole.isEmpty()) {
                return;
            }
            List<User> people = CommissionTargetService.holders(ratesByRole.keySet());
            if (people.isEmpty()) {
                return;
            }
            List<Commission_Target__c> targets = [
                SELECT Id, User__c, Project__c, Reference__c, Designation__c, Target__c, Effective_From__c, Effective_To__c
                FROM Commission_Target__c
                WHERE User__c IN :people AND Reference__c IN :references
                WITH SYSTEM_MODE
                ORDER BY Effective_From__c
            ];
            Map<Id, List<Commission_Target__c>> targetsByUser = new Map<Id, List<Commission_Target__c>>();
            for (Commission_Target__c target : targets) {
                if (!targetsByUser.containsKey(target.User__c)) {
                    targetsByUser.put(target.User__c, new List<Commission_Target__c>());
                }
                targetsByUser.get(target.User__c).add(target);
            }

            // People with the same terms share one notification
            Date today = Date.today();
            String currencyCode = CommissionCatalog.setting().Currency_Code__c;
            List<String> sequence = new List<String>();
            Map<String, Set<Id>> audienceByText = new Map<String, Set<Id>>();
            Map<String, Id> configByText = new Map<String, Id>();
            Map<String, String> titleByText = new Map<String, String>();
            for (User person : people) {
                String role = person.UserRole == null || person.UserRole.DeveloperName == null
                    ? null : person.UserRole.DeveloperName.toLowerCase();
                List<Commission_Rate__c> held = role == null ? null : ratesByRole.get(role);
                if (held == null) {
                    continue;
                }
                for (Commission_Rate__c rate : held) {
                    Commission_Config__c config = configById.get(rate.Config__c);
                    CommissionDto.Designation designation = catalog.get(rate.Designation__c.toLowerCase());
                    String rule = String.isNotBlank(rate.Target_Rule__c) ? rate.Target_Rule__c
                        : (designation == null ? null : designation.targetRule);
                    Decimal target = rule == RULE_NONE ? null : rate.Target__c;
                    if (rule != RULE_NONE && targetsByUser.containsKey(person.Id)) {
                        // The personal target in force today, or on the first day of a configuration still to come
                        Date day = config.Start_Date__c != null && config.Start_Date__c > today ? config.Start_Date__c : today;
                        for (Commission_Target__c personal : targetsByUser.get(person.Id)) {
                            if (personal.Project__c == config.Project__c
                                    && personal.Reference__c == CommissionTargetService.referenceOf(config)
                                    && personal.Designation__c == rate.Designation__c
                                    && CommissionTargetService.coversDay(personal, day)
                                    && !CommissionTargetService.hasNoEffect(personal, rate.Target__c)) {
                                target = personal.Target__c;
                            }
                        }
                    }
                    String designationName = String.isNotBlank(rate.Designation_Label__c) ? rate.Designation_Label__c
                        : (designation == null ? rate.Designation__c : designation.label);
                    String projectName = config.Project__r == null ? '' : config.Project__r.Name;
                    String body = CommissionTargetService.fill(Label.Commission_Notify_Payee_Body, new List<Object>{
                        projectName, config.Name, CommissionTargetService.periodText(config.Start_Date__c, config.End_Date__c),
                        designationName, termsText(rate, target, currencyCode)
                    });
                    String key = String.valueOf(config.Id) + '|' + body;
                    if (!audienceByText.containsKey(key)) {
                        sequence.add(key);
                        audienceByText.put(key, new Set<Id>());
                        configByText.put(key, config.Id);
                        titleByText.put(key, CommissionTargetService.fill(Label.Commission_Notify_Payee_Title, new List<Object>{ projectName }));
                    }
                    audienceByText.get(key).add(person.Id);
                }
            }
            for (String key : sequence) {
                deliver(audienceByText.get(key), titleByText.get(key), key.substringAfter('|'), configByText.get(key), VIEW_TERMS);
            }
        } catch (Exception problem) {
            note(eventName + ' payees', problem);
        }
    }

    // "Target 10 Units · Current rate 10.00% · Exceed rate 12.00%" or "Fee LKR 500,000"
    private static String termsText(Commission_Rate__c rate, Decimal target, String currencyCode) {
        List<String> parts = new List<String>();
        if (target != null) {
            parts.add(CommissionTargetService.fill(Label.Commission_Notify_Term_Target, new List<Object>{
                CommissionTargetService.formatNumber(target), CommissionTargetService.basisText(rate.Target_Basis__c)
            }).trim());
        }
        if (rate.Rate_Type__c == RATE_FLAT) {
            if (rate.Flat_Amount__c != null) {
                parts.add(CommissionTargetService.fill(Label.Commission_Notify_Term_Flat, new List<Object>{
                    currencyCode, CommissionTargetService.formatNumber(rate.Flat_Amount__c)
                }));
            }
        } else {
            if (rate.Current_Rate__c != null) {
                parts.add(CommissionTargetService.fill(Label.Commission_Notify_Term_Current, new List<Object>{ rateText(rate.Current_Rate__c) }));
            }
            if (rate.Exceed_Rate__c != null) {
                parts.add(CommissionTargetService.fill(Label.Commission_Notify_Term_Exceed, new List<Object>{ rateText(rate.Exceed_Rate__c) }));
            }
        }
        return String.join(parts, ' · ');
    }

    // 10 -> 10.00%
    private static String rateText(Decimal value) {
        return value.setScale(2, RoundingMode.HALF_UP).toPlainString() + Label.Commission_Common_Percent_Suffix;
    }

    // ------------------------------------------------------------ target changes

    // To the person, and one summary for Finance and the approvers
    private void targetChanged() {
        List<Commission_Target__c> targets = [
            SELECT Id, User__c, User__r.Name, Target__c, Effective_From__c, Reason__c, Project__c, Project__r.Name,
                Reference__c, Config__c
            FROM Commission_Target__c
            WHERE Id IN :recordIds
            WITH SYSTEM_MODE
            ORDER BY User__r.Name
        ];
        if (targets.isEmpty()) {
            return;
        }
        Set<Id> watchers = idsOf(CommissionAccess.usersWho(CommissionAccess.CONFIGURE));
        watchers.addAll(idsOf(CommissionAccess.usersWho(CommissionAccess.APPROVE)));

        // One summary per project, configuration, day and reason: a save on the screen gives exactly one
        List<String> sequence = new List<String>();
        Map<String, List<String>> linesByScope = new Map<String, List<String>>();
        Map<String, Commission_Target__c> firstByScope = new Map<String, Commission_Target__c>();
        for (Commission_Target__c target : targets) {
            String change = changeTexts != null && changeTexts.containsKey(target.Id)
                ? changeTexts.get(target.Id) : CommissionTargetService.formatNumber(target.Target__c);
            Date fromDay = effectiveFrom != null ? effectiveFrom : target.Effective_From__c;
            String why = String.isNotBlank(reason) ? reason : target.Reason__c;
            String projectName = target.Project__r == null ? '' : target.Project__r.Name;
            deliver(new Set<Id>{ target.User__c }, Label.Commission_Notify_Target_Person_Title,
                CommissionTargetService.fill(Label.Commission_Notify_Target_Person_Body, new List<Object>{
                    actorName, projectName, target.Reference__c, change, CommissionTargetService.formatDate(fromDay), why
                }), target.Config__c, VIEW_TERMS);

            String scope = String.valueOf(target.Project__c) + '|' + target.Reference__c + '|' + String.valueOf(fromDay) + '|' + why;
            if (!linesByScope.containsKey(scope)) {
                sequence.add(scope);
                linesByScope.put(scope, new List<String>());
                firstByScope.put(scope, target);
            }
            linesByScope.get(scope).add(CommissionTargetService.fill(Label.Commission_Notify_Target_Line, new List<Object>{
                target.User__r == null ? '' : target.User__r.Name, change
            }));
        }
        for (String scope : sequence) {
            Commission_Target__c sample = firstByScope.get(scope);
            Date fromDay = effectiveFrom != null ? effectiveFrom : sample.Effective_From__c;
            String why = String.isNotBlank(reason) ? reason : sample.Reason__c;
            deliver(watchers, Label.Commission_Notify_Target_Team_Title,
                CommissionTargetService.fill(Label.Commission_Notify_Target_Team_Body, new List<Object>{
                    actorName, sample.Project__r == null ? '' : sample.Project__r.Name, sample.Reference__c,
                    CommissionTargetService.formatDate(fromDay), String.join(linesByScope.get(scope), '; '), why
                }), sample.Config__c, VIEW_TARGETS);
        }
    }

    // ------------------------------------------------------------ sending

    // A bell notification to these users that opens the Commission Setup tab: on the configuration when one is
    // given, else on the overview. Never throws.
    public static void send(Set<Id> userIds, String title, String body, Id configId) {
        deliver(userIds, title, body, configId, configId == null ? VIEW_OVERVIEW : VIEW_REVIEW);
    }

    private static void deliver(Set<Id> userIds, String title, String body, Id configId, String view) {
        try {
            Set<Id> recipients = new Set<Id>();
            if (userIds != null) {
                for (Id userId : userIds) {
                    if (userId != null) {
                        recipients.add(userId);
                    }
                }
            }
            if (recipients.isEmpty() || String.isBlank(title)) {
                return;
            }
            String text = String.isBlank(body) ? title : body;
            if (Test.isRunningTest()) {
                Sent entry = new Sent();
                entry.userIds = recipients;
                entry.title = title;
                entry.body = text;
                entry.configId = configId;
                entry.view = view;
                sentLog.add(entry);
            }
            Id notificationType = notificationTypeId();
            if (notificationType == null) {
                System.debug(LoggingLevel.ERROR, '>>> [Commission] Notification type not found, nothing sent: ' + title);
            } else {
                String target = pageReference(configId, view);
                // One send takes at most 500 users; a failed part does not stop the others
                for (Set<String> part : chunks(recipients, MAX_RECIPIENTS)) {
                    try {
                        if (Limits.getDmlStatements() >= Limits.getLimitDmlStatements() - 1) {
                            System.debug(LoggingLevel.ERROR, '>>> [Commission] Limit reached, notification not sent: ' + title);
                            break;
                        }
                        Messaging.CustomNotification notification = new Messaging.CustomNotification();
                        notification.setNotificationTypeId(notificationType);
                        notification.setTitle(title.abbreviate(TITLE_LENGTH));
                        notification.setBody(text.abbreviate(BODY_LENGTH));
                        notification.setTargetPageRef(target);
                        // A test builds the notification but never hands it over: its users can be real people
                        if (!Test.isRunningTest()) {
                            notification.send(part);
                        }
                    } catch (Exception problem) {
                        note('send ' + title, problem);
                    }
                }
            }
            email(recipients, title, text);
        } catch (Exception problem) {
            note('send ' + title, problem);
        }
    }

    // {"type":"standard__navItemPage","attributes":{"apiName":"Commission_Setup"},"state":{"c__view":"review","c__id":"<config id>"}}
    @TestVisible
    private static String pageReference(Id configId, String view) {
        Map<String, Object> state = new Map<String, Object>{ 'c__view' => view };
        if (configId != null) {
            state.put('c__id', String.valueOf(configId));
        }
        return JSON.serialize(new Map<String, Object>{
            'type' => 'standard__navItemPage',
            'attributes' => new Map<String, Object>{ 'apiName' => TAB_NAME },
            'state' => state
        });
    }

    // The custom notification type named in the Commission Setting; null when it does not exist
    private static Id notificationTypeId() {
        if (!typeResolved) {
            typeResolved = true;
            String name = CommissionCatalog.setting().Notification_Type__c;
            if (String.isNotBlank(name)) {
                List<CustomNotificationType> found = [
                    SELECT Id FROM CustomNotificationType WHERE DeveloperName = :name.trim() WITH SYSTEM_MODE LIMIT 1
                ];
                if (!found.isEmpty()) {
                    typeId = found[0].Id;
                }
            }
        }
        return typeId;
    }

    @TestVisible
    private static List<Set<String>> chunks(Set<Id> userIds, Integer size) {
        List<Set<String>> parts = new List<Set<String>>();
        Set<String> part = new Set<String>();
        for (Id userId : userIds) {
            if (part.size() == size) {
                parts.add(part);
                part = new Set<String>();
            }
            part.add(String.valueOf(userId));
        }
        if (!part.isEmpty()) {
            parts.add(part);
        }
        return parts;
    }

    // The same text as a plain email, only when the Commission Setting asks for it
    private static void email(Set<Id> userIds, String title, String body) {
        if (CommissionCatalog.setting().Email_Enabled__c != true) {
            return;
        }
        try {
            // The sender may need two attempts for one list of emails
            if (Limits.getEmailInvocations() + 2 > Limits.getLimitEmailInvocations()) {
                return;
            }
            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Id userId : userIds) {
                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                message.setTargetObjectId(userId);
                message.setSaveAsActivity(false);
                message.setSubject(title.abbreviate(TITLE_LENGTH));
                message.setPlainTextBody(body);
                emails.add(message);
            }
            emailsPrepared += emails.size();
            PartnerEmailSender.send(emails);
        } catch (Exception problem) {
            note('email ' + title, problem);
        }
    }

    // ------------------------------------------------------------ helpers

    private static Set<Id> idsOf(List<User> users) {
        Set<Id> ids = new Set<Id>();
        if (users != null) {
            for (User person : users) {
                ids.add(person.Id);
            }
        }
        return ids;
    }

    private static String nameOf(User person) {
        return person == null || String.isBlank(person.Name) ? Label.Commission_Notify_Someone : person.Name;
    }

    private static void note(String what, Exception problem) {
        System.debug(LoggingLevel.ERROR, '>>> [Commission] Notification failed (' + what + '): '
            + problem.getMessage() + ' ' + problem.getStackTraceString());
    }
}