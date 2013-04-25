#import "NSEnumerable+Utilities.h"
#import "NSOrderedSet+BlocksKit.h"
#import "NSArray+BlocksKit.h"
#import "NSOrderedSet+BlocksKit.h"
#import "NSSet+BlocksKit.h"

#import "GKTurnBasedMatch+SHGameCenter.h"

#import "SHGameCenter.h"

#include "SHGameCenter.privates"

static NSString * const SHGameMatchEventTurnKey     = @"SHGameMatchEventTurnKey";
static NSString * const SHGameMatchEventEndedKey    = @"SHGameMatchEventEndedKey";
static NSString * const SHGameMatchEventInvitesKey  = @"SHGameMatchEventInvitesKey";

@interface SHTurnBasedMatchManager : NSObject
<GKTurnBasedEventHandlerDelegate>
@property(nonatomic,strong) NSMapTable          * mapBlocks;

#pragma mark -
#pragma mark Singleton Methods
+(instancetype)sharedManager;

@end

@implementation SHTurnBasedMatchManager
#pragma mark -
#pragma mark Init & Dealloc
-(instancetype)init; {
  self = [super init];
  if (self) {
    GKTurnBasedEventHandler.sharedTurnBasedEventHandler.delegate = self;
    self.mapBlocks    = [NSMapTable weakToStrongObjectsMapTable];
  }
  
  return self;
}

#pragma mark -
#pragma mark Singleton Methods
+(instancetype)sharedManager; {
  static SHTurnBasedMatchManager *_sharedInstance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _sharedInstance = [[SHTurnBasedMatchManager alloc] init];
    
  });
  
  return _sharedInstance;
  
}


#pragma mark -
#pragma mark <GKTurnBasedEventHandlerDelegate>
-(void)handleInviteFromGameCenter:(NSArray *)playersToInvite; {
  for (NSDictionary * blocks in self.mapBlocks.objectEnumerator) {
    SHGameMatchEventInvitesBlock block = blocks[SHGameMatchEventInvitesKey];
    block(playersToInvite.toOrderedSet);
  }
  
}

-(void)handleTurnEventForMatch:(GKTurnBasedMatch *)match didBecomeActive:(BOOL)didBecomeActive; {
  [SHGameCenter updateCachePlayersFromPlayerIdentifiers:match.SH_playerIdentifiers.set withCompletionBlock:^{
    for (NSDictionary * blocks in self.mapBlocks.objectEnumerator) {
      SHGameMatchEventTurnBlock block = blocks[SHGameMatchEventTurnKey];
      block(match, didBecomeActive);
    }
  }];
  
  
}

// handleMatchEnded is called when the match has ended.
-(void)handleMatchEnded:(GKTurnBasedMatch *)match; {
  [SHGameCenter updateCachePlayersFromPlayerIdentifiers:match.SH_playerIdentifiers.set withCompletionBlock:^{
    for (NSDictionary * blocks in self.mapBlocks.objectEnumerator) {
      SHGameMatchEventEndedBlock block = blocks[SHGameMatchEventEndedKey];
      block(match);
    }
  }];
  
}

@end

@implementation GKTurnBasedMatch (SHGameCenter)


#pragma mark -
#pragma mark Player Getters
-(GKTurnBasedParticipant *)SH_meAsParticipant; {
  return [self.participants match:^BOOL(GKTurnBasedParticipant * participant) {
    return [participant SH_isEqual:GKLocalPlayer.SH_me];
  }];
}

-(NSOrderedSet *)SH_participantsWithoutMe; {
  NSOrderedSet * participantsWithoutMe = nil;
  if(self.SH_meAsParticipant)
   participantsWithoutMe = [self SH_rejectParticipants:@[self.SH_meAsParticipant].toSet];
  else
    participantsWithoutMe = self.participants.toOrderedSet;
  return participantsWithoutMe;
}

-(NSOrderedSet *)SH_participantsWithoutCurrentParticipant; {
  NSOrderedSet * participantsWithoutCurrentParticipant = nil;
  if(self.currentParticipant)
    participantsWithoutCurrentParticipant = [self SH_rejectParticipants:@[self.currentParticipant].toSet];
  else
    participantsWithoutCurrentParticipant = self.participants.toOrderedSet;
  return  participantsWithoutCurrentParticipant;
}

-(NSOrderedSet *)SH_nextParticipantsInLine; {
  return [self.SH_participantsWithoutCurrentParticipant sortedArrayUsingComparator:^NSComparisonResult(GKTurnBasedParticipant * obj1, GKTurnBasedParticipant * obj2) {
    if(obj1.lastTurnDate == nil)
      return NSOrderedAscending;
    if (obj2.lastTurnDate == nil)
      return NSOrderedDescending;

    return [obj1.lastTurnDate compare:obj2.lastTurnDate];
  }].toOrderedSet;
}

-(NSOrderedSet *)SH_playerIdentifiers; {
  return [self.participants map:^id(GKTurnBasedParticipant * obj) { return obj.playerID; }].toOrderedSet;
}

#pragma mark -
#pragma mark Observer
+(void)SH_setObserver:(id)theObserver
matchEventTurnBlock:(SHGameMatchEventTurnBlock)theMatchEventTurnBlock
matchEventEndedBlock:(SHGameMatchEventEndedBlock)theMatchEventEndedBlock
matchEventInvitesBlock:(SHGameMatchEventInvitesBlock)theMatchEventInvitesBlock; {
  
  NSAssert(theObserver, @"Must pass an observer!");
  
  NSMutableDictionary * blocks = @{}.mutableCopy;
  
  if(theMatchEventTurnBlock)    blocks[SHGameMatchEventTurnKey]    = [theMatchEventTurnBlock copy];
  if(theMatchEventEndedBlock)   blocks[SHGameMatchEventEndedKey]   = [theMatchEventEndedBlock copy];
  if(theMatchEventInvitesBlock) blocks[SHGameMatchEventInvitesKey] = [theMatchEventInvitesBlock copy];
  
  [SHTurnBasedMatchManager.sharedManager.mapBlocks setObject:blocks.copy forKey:theObserver];
  
}


#pragma mark -
#pragma mark Conditions
-(BOOL)SH_isMyTurn; {
  return [self.currentParticipant SH_isEqual:GKLocalPlayer.SH_me];
}
-(BOOL)SH_hasIncompleteParticipants; {
  return [self.participants any:^BOOL(GKTurnBasedParticipant * participant) {
    return participant.SH_isActiveOrInvited == NO;
  }];
}

-(BOOL)SH_isMatchStatusOpen; {
  return self.status == GKTurnBasedMatchStatusOpen;
}
-(BOOL)SH_isMatchStatusMatching; {
  return self.status == GKTurnBasedMatchStatusMatching;
}
-(BOOL)SH_isMatchStatusEnded; {
  return self.status == GKTurnBasedMatchStatusEnded;
}

-(BOOL)SH_isMatchStatusUnknown; {
  return self.status == GKTurnBasedMatchStatusUnknown;
}

#pragma mark -
#pragma mark Player
-(void)SH_requestPlayersWithBlock:(SHGameListsBlock)theBlock; {
  [GKPlayer loadPlayersForIdentifiers:self.SH_playerIdentifiers.array withCompletionHandler:^(NSArray *players, NSError *error) {
    theBlock(players.toOrderedSet, error);
  }];
}




#pragma mark -
#pragma mark Equal
-(BOOL)isEqualToMatch:(id)object; {
  BOOL isEqual = NO;
  if([object respondsToSelector:@selector(matchID)])
   isEqual = [self.matchID isEqualToString:((GKTurnBasedMatch *)object).matchID];
  return isEqual;
}

#pragma mark -
#pragma mark Match Getters
+(void)SH_requestMatchesWithBlock:(SHGameListsBlock)theBlock; {
  [GKTurnBasedMatch loadMatchesWithCompletionHandler:^(NSArray *matches, NSError *error) {
    theBlock(matches.toOrderedSet, error);
  }];
}



#pragma mark -
#pragma mark Match Setters
//Need to refactor here. Things are still uncertain. 
-(void)SH_resignWithBlock:(SHGameMatchBlock)theBlock; {
//  [self.participants each:^(GKTurnBasedParticipant * participant) {
//    participant.matchOutcome = GKTurnBasedMatchOutcomeQuit;
//  }];
  
//  if(self.SH_isMatchStatusEnded)
//    theBlock(self,nil);
//  else
    [self endMatchInTurnWithMatchData:self.matchData completionHandler:^(NSError *error) {
      if(error)
        [self participantQuitOutOfTurnWithOutcome:GKTurnBasedMatchOutcomeQuit withCompletionHandler:^(NSError *error) {
          theBlock(self, error);
        }];
      else
        theBlock(self,error);
    }];

  

}

-(void)SH_deleteWithBlock:(SHGameMatchBlock)theBlock; {
  
  
  [self SH_resignWithBlock:^(GKTurnBasedMatch *match, NSError *error) {
    if(error) theBlock(match, error);
    else 
    [self removeWithCompletionHandler:^(NSError *error) {
      theBlock(self, error);
    }];
  }];
}
#pragma mark -
#pragma mark Helpers
-(NSOrderedSet *)SH_rejectParticipants:(NSSet *)theParticipantsToRject; {
 return [self.participants reject:^BOOL(GKTurnBasedParticipant * participant) {
   return[theParticipantsToRject match:^BOOL(GKTurnBasedParticipant * participantToRemove) {
     return [participant SH_isEqual:participantToRemove];
   }];
  }].toOrderedSet;
}




@end
