/**
 * The sender of the emails this project sends to channel partners.
 *
 * An email sent from Apex normally goes out in the name of whoever triggered it (the approver, for example). When that
 * person's mailbox is on a public service such as Gmail, Salesforce cannot sign the email and the partner's mail
 * provider blocks it. With the Email Sender Address of the Partner Portal Setting filled in, the emails are sent from
 * that verified Organization-Wide Email Address instead. Blank, unknown or not verified: they go out as the running
 * user, as before.
 *
 * Also what the classes that build an email from a template share: filling in what a template leaves to Apex,
 * written [[Like This]], and the optional reason of a rejection.
 */
public without sharing class PartnerEmailSender {

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

    // Looked up once per transaction
    @TestVisible
    private static Boolean resolved = false;
    @TestVisible
    private static Id resolvedSender;

    // The Organization-Wide Email Address the partner emails are sent from; null: the running user sends them
    public static Id senderId() {
        if (!resolved) {
            resolved = true;
            String address = setting == null ? null : setting.Email_Sender_Address__c;
            if (String.isNotBlank(address)) {
                List<OrgWideEmailAddress> senders = [
                    SELECT Id FROM OrgWideEmailAddress WHERE Address = :address.trim() AND IsVerified = true WITH SYSTEM_MODE LIMIT 1
                ];
                if (senders.isEmpty()) {
                    System.debug(LoggingLevel.ERROR, '>>> [PartnerPortal] Email sender not found or not verified: ' + address);
                } else {
                    resolvedSender = senders[0].Id;
                }
            }
        }
        return resolvedSender;
    }

    // Puts the sender on the emails; they are left as they are when no sender is set up
    public static void apply(List<Messaging.SingleEmailMessage> emails) {
        Id sender = senderId();
        if (sender == null) {
            return;
        }
        for (Messaging.SingleEmailMessage email : emails) {
            email.setOrgWideEmailAddressId(sender);
        }
    }

    // Sends the emails from the sender. An email the sender could not send (a profile that may not use the address,
    // for example) goes out as the running user, so a wrong set-up never costs the partner an email. One result per
    // email, in the same order.
    public static List<Messaging.SendEmailResult> send(List<Messaging.SingleEmailMessage> emails) {
        if (senderId() == null) {
            return Messaging.sendEmail(emails, false);
        }
        apply(emails);
        List<Messaging.SendEmailResult> results;
        try {
            results = Messaging.sendEmail(emails, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '>>> [PartnerPortal] Emails not sent from the email sender: ' + e.getMessage());
        }
        List<Integer> failed = new List<Integer>();
        List<Messaging.SingleEmailMessage> again = new List<Messaging.SingleEmailMessage>();
        for (Integer i = 0; i < emails.size(); i++) {
            if (results == null || !results[i].isSuccess()) {
                emails[i].setOrgWideEmailAddressId(null);
                failed.add(i);
                again.add(emails[i]);
            }
        }
        if (again.isEmpty()) {
            return results;
        }
        if (results != null) {
            System.debug(LoggingLevel.ERROR, '>>> [PartnerPortal] Sent as the running user instead of the email sender: ' + again.size());
        }
        List<Messaging.SendEmailResult> retried = Messaging.sendEmail(again, false);
        if (results == null) {
            return retried;
        }
        for (Integer n = 0; n < failed.size(); n++) {
            results[failed[n]] = retried[n];
        }
        return results;
    }

    // ---------- what a template leaves for Apex to fill in ----------

    // In a template, [[Reason]] stands for an approver's comment. Without a comment, the HTML version loses the part
    // between <!--reason--> and <!--/reason-->, and the text version the line that holds [[Reason]].
    public static final String REASON_TOKEN = '[[Reason]]';
    // The two markers, whatever their spacing or capitals, and everything between them
    private static final String REASON_PART = '(?is)<!--\\s*reason\\s*-->.*?<!--\\s*/reason\\s*-->';

    // Puts the values in place of their [[Tokens]] in a template's subject or text. A classic template drops the merge
    // fields it does not know, and cannot reach a record through another (the customer's name through a visit), so what
    // Apex fills in is not written {!Like.This}.
    public static String fill(String text, Map<String, String> values) {
        String filled = text == null ? '' : text;
        for (String token : values.keySet()) {
            filled = filled.replace(token, values.get(token) == null ? '' : values.get(token));
        }
        return filled;
    }

    // The same in a template's HTML: nothing in a value is read as markup, and its line breaks stay
    public static String fillHtml(String html, Map<String, String> values) {
        String filled = html == null ? '' : html;
        for (String token : values.keySet()) {
            filled = filled.replace(token, values.get(token) == null ? '' : asHtml(values.get(token)));
        }
        return filled;
    }

    // The HTML of a template with the reason in its place; without a reason, without the part kept for it. A template
    // that has no place for the reason gets the line as its last paragraph.
    public static String htmlWithReason(String html, String reason, String lineWithoutPlace) {
        html = html == null ? '' : html;
        if (reason == null) {
            html = html.replaceAll(REASON_PART, '');
            if (html.contains(REASON_TOKEN)) {
                // A token outside the markers: its heading stays, with nothing under it
                System.debug(LoggingLevel.ERROR, 'Email template: ' + REASON_TOKEN + ' is not between <!--reason--> and <!--/reason-->');
            }
            return html.replace(REASON_TOKEN, '');
        }
        if (html.contains(REASON_TOKEN)) {
            return html.replace(REASON_TOKEN, asHtml(reason));
        }
        String line = '<p>' + asHtml(String.isBlank(lineWithoutPlace) ? reason : lineWithoutPlace) + '</p>';
        Integer bodyEnd = html.toLowerCase().lastIndexOf('</body>');
        return bodyEnd < 0 ? html + line : html.substring(0, bodyEnd) + line + html.substring(bodyEnd);
    }

    // The text of a template with the reason in its place; without a reason, without the line that holds it. A template
    // that has no place for the reason gets the line as its last one.
    public static String textWithReason(String text, String reason, String lineWithoutPlace) {
        text = text == null ? '' : text;
        if (text.contains(REASON_TOKEN)) {
            return reason != null ? text.replace(REASON_TOKEN, reason)
                : text.replaceAll('(?m)^.*' + Pattern.quote(REASON_TOKEN) + '.*(\\r?\\n){0,2}', '');
        }
        return reason == null ? text : text + '\n\n' + (String.isBlank(lineWithoutPlace) ? reason : lineWithoutPlace);
    }

    // A value as HTML: nothing in it is read as markup, and its line breaks stay
    public static String asHtml(String value) {
        return value == null ? '' : value.escapeHtml4().replace('\r\n', '\n').replace('\n', '<br>');
    }
}