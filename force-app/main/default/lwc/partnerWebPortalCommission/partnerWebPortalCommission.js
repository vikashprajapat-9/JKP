import { LightningElement } from 'lwc';

// SAMPLE DATA from the Figma (p75/p76). There is no commission object yet.
// Replace with Apex data once the backend is built; keep the same shape.
const SAMPLE_COMMISSIONS = [
    { id: 'ID-1288', project: 'JK Kingsland', unit: 'B2-210', buyer: 'Ramesh', type: '2 BHK', status: 'Yet to Claim', salesperson: 'Sahil', soId: 'S/046789', purchasePrice: 'LKR 10,000', commission: 'LKR 335 and 10%' },
    { id: 'ID-34657', project: 'JK Pallaciya', unit: 'B2-210', buyer: 'Ramesh', type: '2 BHK', status: 'Approved', salesperson: 'Sahil', soId: 'S/046790', purchasePrice: 'LKR 10,000', commission: 'LKR 335 and 10%' },
    { id: 'ID-67657', project: 'JK FairyTale', unit: 'B2-210', buyer: 'Ramesh', type: '2 BHK', status: 'Claim Submitted', salesperson: 'Sahil', soId: 'S/046791', purchasePrice: 'LKR 10,000', commission: 'LKR 335 and 10%' },
    { id: 'ID-14657', project: 'JK Kingsland', unit: 'B2-210', buyer: 'Ramesh', type: '2 BHK', status: 'Claim Credited', salesperson: 'Sahil', soId: 'S/046792', purchasePrice: 'LKR 10,000', commission: 'LKR 335 and 10%' },
    { id: 'ID-24573', project: 'Savera Residency', unit: 'B2-210', buyer: 'Ramesh', type: '2 BHK', status: 'Rejected', salesperson: 'Sahil', soId: 'S/046793', purchasePrice: 'LKR 10,000', commission: 'LKR 335 and 10%' }
];

const BADGE_CLASS = {
    'Yet to Claim': 'badge badge-yet',
    'Approved': 'badge badge-approved',
    'Claim Submitted': 'badge badge-submitted',
    'Claim Credited': 'badge badge-credited',
    'Rejected': 'badge badge-rejected'
};

const CLAIMABLE_STATUS = 'Yet to Claim';

export default class PartnerWebPortalCommission extends LightningElement {

    commissions = SAMPLE_COMMISSIONS.map(c => ({ ...c }));
    expandedId = null;
    submittedId = null;

    get rows() {
        return this.commissions.map(c => {
            const expanded = c.id === this.expandedId;
            return {
                ...c,
                expanded,
                badgeClass: BADGE_CLASS[c.status] || 'badge',
                canClaim: c.status === CLAIMABLE_STATUS,
                rowClass: expanded ? 'row expanded' : 'row',
                chevronClass: expanded ? 'chevron open' : 'chevron',
                toggleLabel: (expanded ? 'Hide details for ' : 'Show details for ') + c.id
            };
        });
    }

    get hasRows() {
        return this.commissions.length > 0;
    }

    get showSuccess() {
        return this.submittedId !== null;
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.expandedId = this.expandedId === id ? null : id;
    }

    handleRequestClaim(event) {
        const id = event.currentTarget.dataset.id;
        // TODO: call Apex to submit the claim. UI only for now.
        this.commissions = this.commissions.map(c =>
            c.id === id ? { ...c, status: 'Claim Submitted' } : c
        );
        this.submittedId = id;
    }

    handleCloseSuccess() {
        this.submittedId = null;
    }
}