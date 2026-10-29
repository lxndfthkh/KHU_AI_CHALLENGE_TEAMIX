"""Firestore adapter: reads precede all writes; transaction retries are SDK-managed."""
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from service import Missing

class Transaction:
    def __init__(self, db, transaction):
        self.db, self.tx = db, transaction
    def one(self, path):
        snap = self.db.document(path).get(transaction=self.tx)
        return snap.to_dict() if snap.exists else None
    def many(self, path):
        return {d.id: d.to_dict() for d in self.db.collection(path).stream(transaction=self.tx)}
    def load(self, g, a):
        base=f'groups/{g}/activities/{a}'
        activity=self.one(base)
        if activity is None: raise Missing()
        members=self.many(f'groups/{g}/members')
        questions=self.many(base+'/questions')
        for key,q in questions.items(): q['id']=key
        version=activity.get('publishedVersionId')
        published_meta=self.one(base+'/teamVersions/'+version) if version else {}
        teams=self.many(base+'/teamVersions/'+version+'/teams') if version else {}
        published={uid:t for t,v in teams.items() for uid in v.get('members',[])}
        query=self.db.collection('privatePreferences').where(filter=FieldFilter('groupId','==',g)).where(filter=FieldFilter('activityId','==',a))
        prefs={d.id:d.to_dict() for d in query.stream(transaction=self.tx)}
        return {'activity':activity,'members':members,'questions':questions,
                'applications':self.many(base+'/applications'),'draft':self.one(base+'/draft/current') or {},
                'meta':self.one(base+'/private/meta') or {},'preferences':prefs,
                'published':published,'publishedMeta':published_meta or {},
                'notified':self.many(base+'/lastNotified')}
    def set(self, path, value, merge=False):
        self.tx.set(self.db.document(path),value,merge=merge)

class FirestoreRepository:
    def __init__(self, db): self.db=db
    def atomic(self, callback):
        @firestore.transactional
        def execute(tx): return callback(Transaction(self.db,tx))
        return execute(self.db.transaction())
