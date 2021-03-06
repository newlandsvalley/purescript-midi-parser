module MidiPerformance (toPerformance) where

import Control.Monad.State as ControlState
import Audio.SoundFont (MidiNote)
import Data.Midi as Midi
import Data.Tuple (Tuple(..), fst, snd)
-- import Data.Array ((:), reverse)
import Data.List (List(..), index, reverse, (:))
import Data.Maybe (Maybe, fromMaybe)
import Data.Int (toNumber)
import Prelude (bind, pure, (*), (+), (/), (==))

-- | the state to thread through the computation
-- | which translates MIDI to a Web-Audio graph
type TState =
    { ticksPerBeat :: Int        -- taken from the MIDI header
    , tempo :: Int               -- this will almost certainly be reset at the start of the MIDI file
    , noteOffset :: Number       -- the offset in time of the next note to be processed
    , notes :: List MidiNote    -- the ever-increasing set of generated notes
    }

type TransformationState =
  Tuple TState (List MidiNote)

initialTState :: Int -> TState
initialTState ticksPerBeat =
  { ticksPerBeat : ticksPerBeat
  , tempo : 1000000
  , noteOffset : 0.0
  , notes : Nil
  }

initialTransformationState :: Int -> TransformationState
initialTransformationState ticksPerBeat =
  Tuple (initialTState ticksPerBeat) Nil

-- | transform a Midi.Recording to a MIDI performance
-- | which is simply an array of MIDI notes, each timed to
-- | be played at the appropriate time offset
toPerformance :: Midi.Recording -> Int -> List MidiNote
toPerformance (Midi.Recording recording) trackNo =
  let
    mtrack :: Maybe Midi.Track
    mtrack = index recording.tracks trackNo
    Midi.Track track = fromMaybe (Midi.Track Nil) mtrack
    Midi.Header header = recording.header
  in
    do
      ControlState.evalState (transformTrack track) (initialTransformationState header.ticksPerBeat)

transformTrack :: List Midi.Message -> ControlState.State TransformationState (List MidiNote)
transformTrack Nil =
  do
    retrieveMelody
transformTrack (Cons m ms) =
  do
    _ <- transformMessage m
    transformTrack ms

transformMessage :: Midi.Message -> ControlState.State TransformationState (List MidiNote)
transformMessage m =
  case m of
    Midi.Message ticks (Midi.Tempo tempo) ->
      accumulateTempo ticks tempo
    Midi.Message ticks (Midi.NoteOn channel pitch velocity) ->
      accumulateNoteOn channel ticks pitch velocity
    Midi.Message ticks _ ->
      accumulateTicks ticks

accumulateNoteOn :: Int -> Int -> Int -> Int -> ControlState.State TransformationState (List MidiNote)
accumulateNoteOn channel ticks pitch velocity =
  do
    tpl <- ControlState.get
    let
      recording = snd tpl
      tstate = fst tpl
      offsetDelta = ticksToTime ticks tstate
      notes =
        if (pitch == 0) then
          tstate.notes
        else
          (buildNote channel pitch velocity (tstate.noteOffset + offsetDelta)) : tstate.notes
      tstate' = tstate { noteOffset = tstate.noteOffset + offsetDelta
                       , notes = notes
                       }
      tpl' = Tuple tstate' recording
    _ <- ControlState.put tpl'
    pure recording

accumulateTicks :: Int -> ControlState.State TransformationState (List MidiNote)
accumulateTicks ticks =
  do
    tpl <- ControlState.get
    let
      recording = snd tpl
      tstate = fst tpl
      offsetDelta = ticksToTime ticks tstate
      tstate' = tstate { noteOffset = tstate.noteOffset + offsetDelta }
      tpl' = Tuple tstate' recording
    _ <- ControlState.put tpl'
    pure recording

accumulateTempo :: Int -> Int -> ControlState.State TransformationState (List MidiNote)
accumulateTempo ticks tempo =
  do
    tpl <- ControlState.get
    let
      recording = snd tpl
      tstate = fst tpl
      offsetDelta = ticksToTime ticks tstate
      tstate' = tstate { noteOffset = tstate.noteOffset + offsetDelta
                       , tempo = tempo
                       }
      tpl' = Tuple tstate' recording
    _ <- ControlState.put tpl'
    pure recording

ticksToTime  :: Int -> TState -> Number
ticksToTime ticks tstate =
  (toNumber ticks * toNumber tstate.tempo) / (toNumber tstate.ticksPerBeat * 1000000.0)

retrieveMelody :: ControlState.State TransformationState (List MidiNote)
retrieveMelody =
  do
    tpl <- ControlState.get
    let
      tstate = fst tpl
      recording = reverse tstate.notes
    pure recording

buildNote :: Int -> Int -> Int -> Number -> MidiNote
buildNote channel pitch velocity noteOffset =
  let
    maxVolume = 127
    gain =
      toNumber velocity / toNumber maxVolume
  in
    { channel: channel, id: pitch, timeOffset: noteOffset, duration : 1.0, gain : gain }
