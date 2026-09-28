import { LightningElement, wire } from 'lwc';
import getMyTeam from '@salesforce/apex/PartnerWebPortalMyTeamController.getMyTeam';

export default class PartnerWebPortalMyTeam extends LightningElement {

    stats = { totalLeads: 0, totalBookings: 0, totalExecutives: 0 };
    members = [];
    error;

    @wire(getMyTeam)
    wiredTeam({ data, error }) {
        if (data) {
            this.stats = data.stats || this.stats;
            this.members = (data.members || []).map(m => ({
                ...m,
                avatarClass: 'avatar ' + (m.avatarColorClass || 'avatar-blue')
            }));
        } else if (error) {
            this.error = error.body ? error.body.message : 'Failed to load team';
            console.error('My Team wire error:', error);
        }
    }

    handleAddExecutive() {
        console.log('Add Executive clicked');
        // TODO: open modal / navigate to new-user flow
    }
}