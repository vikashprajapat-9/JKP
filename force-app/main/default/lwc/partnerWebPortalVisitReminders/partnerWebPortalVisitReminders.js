import { LightningElement, api } from 'lwc';
import getReminders from '@salesforce/apex/PartnerVisitReminders.getReminders';
import markVisited from '@salesforce/apex/PartnerVisitReminders.markVisited';
import markNotVisited from '@salesforce/apex/PartnerVisitReminders.markNotVisited';
import TODAY from '@salesforce/label/c.Partner_Reminder_Today';
import TOMORROW from '@salesforce/label/c.Partner_Reminder_Tomorrow';
import TO_UPDATE from '@salesforce/label/c.Partner_Reminder_To_Update';
import TO_UPDATE_HINT from '@salesforce/label/c.Partner_Reminder_To_Update_Hint';
import NONE from '@salesforce/label/c.Partner_Reminder_None';
import VISITED from '@salesforce/label/c.Partner_Reminder_Visited';
import NOT_VISITED from '@salesforce/label/c.Partner_Reminder_Not_Visited';
import TITLE from '@salesforce/label/c.Partner_Reminder_Title';
import NOT_VISITED_CONFIRM from '@salesforce/label/c.Partner_Visit_Not_Visited_Confirm';
import VISITED_CONFIRM from '@salesforce/label/c.Partner_Visit_Visited_Confirm';
import LOAD_ERROR from '@salesforce/label/c.Partner_Reminder_Load_Error';

function errorText(error, fallback) {
    return (error && error.body && error.body.message) || (error && error.message) || fallback;
}

// The Site Visit Reminders (PartnerVisitReminders): today's visits, tomorrow's, and the ones whose day has passed and
// that are not updated yet, which the agent marks Visited or Did not visit here. The portal shows them in its bell only
// (compact), where it says when there is none. Fires "reminderchange" (bubbles, composed; detail: { count, updated })
// when it loads, and with updated true after the agent updated a visit.
export default class PartnerWebPortalVisitReminders extends LightningElement {
    @api compact = false;

    reminders;
    loading = true;
    busy = false;
    error;
    message;
    // The visit and action waiting for the agent's confirmation
    asking;
    labels = { title: TITLE, none: NONE, visited: VISITED, notVisited: NOT_VISITED };

    _version;
    @api
    get version() {
        return this._version;
    }
    set version(value) {
        const changed = this._version !== undefined && value !== this._version;
        this._version = value;
        if (changed) {
            this.load();
        }
    }

    connectedCallback() {
        this.load();
    }

    async load(updated = false) {
        this.loading = !this.reminders;
        try {
            this.reminders = await getReminders();
            this.error = undefined;
            this.fireChange(updated);
        } catch (error) {
            this.error = errorText(error, LOAD_ERROR);
        } finally {
            this.loading = false;
        }
    }

    fireChange(updated) {
        const count = this.reminders ? this.reminders.count || 0 : 0;
        this.dispatchEvent(new CustomEvent('reminderchange', { detail: { count, updated }, bubbles: true, composed: true }));
    }

    get hasReminders() {
        const r = this.reminders;
        return Boolean(r) && (r.today.length + r.tomorrow.length + r.toUpdate.length) > 0;
    }

    // Not compact, the section shows only when there is something (or something to say); the bell is compact
    get showSection() {
        return this.compact || this.hasReminders || Boolean(this.error) || Boolean(this.message);
    }

    get sectionClass() {
        return this.compact ? 'reminders reminders_compact' : 'reminders';
    }

    get confirmLabel() {
        return this.busy ? 'Saving…' : 'Yes';
    }

    get groups() {
        if (!this.reminders) {
            return [];
        }
        const groups = [
            { key: 'toUpdate', title: TO_UPDATE, hint: TO_UPDATE_HINT, icon: 'utility:warning', items: this.reminders.toUpdate, actions: true },
            { key: 'today', title: TODAY, icon: 'utility:event', items: this.reminders.today, actions: true },
            { key: 'tomorrow', title: TOMORROW, icon: 'utility:clock', items: this.reminders.tomorrow, actions: false }
        ];
        return groups
            .filter((group) => group.items.length > 0)
            .map((group) => ({
                ...group,
                count: group.items.length,
                className: 'group group_' + group.key,
                items: group.items.map((item) => {
                    const confirming = Boolean(this.asking) && this.asking.id === item.visitId;
                    const notVisited = confirming && this.asking.action === 'notVisited';
                    return {
                        ...item,
                        metaText: [item.projectName, item.visitName].filter(Boolean).join(' · '),
                        showActions: group.actions,
                        disabled: !item.canUpdate || this.busy,
                        confirming,
                        confirmText: notVisited ? NOT_VISITED_CONFIRM : VISITED_CONFIRM,
                        confirmClass: notVisited ? 'btn btn_warn' : 'btn btn_primary'
                    };
                })
            }));
    }

    handleAsk(event) {
        this.asking = { id: event.currentTarget.dataset.id, action: event.currentTarget.dataset.action };
        this.error = undefined;
        this.message = undefined;
    }

    handleBack() {
        this.asking = undefined;
    }

    async handleConfirm() {
        if (!this.asking) {
            return;
        }
        const { id, action } = this.asking;
        this.busy = true;
        this.error = undefined;
        try {
            this.message = action === 'visited' ? await markVisited({ visitId: id }) : await markNotVisited({ visitId: id });
            this.asking = undefined;
            await this.load(true);
        } catch (error) {
            this.error = errorText(error, LOAD_ERROR);
        } finally {
            this.busy = false;
        }
    }

    handleCloseMessage() {
        this.message = undefined;
    }

    handleCloseError() {
        this.error = undefined;
    }
}