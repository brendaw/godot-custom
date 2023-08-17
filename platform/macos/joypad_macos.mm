/**************************************************************************/
/*  joypad_macos.mm                                                       */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#import "joypad_macos.h"
#include <Foundation/Foundation.h>

#import "os_macos.h"

#include "core/config/project_settings.h"
#include "core/os/keyboard.h"
#include "core/string/ustring.h"
#include "main/main.h"

@implementation Joypad

- (instancetype)init {
	self = [super init];
	return self;
}
- (instancetype)init:(GCController *)controller {
	self = [super init];
	self.controller = controller;
	self.pattern_player = nil;

	CHHapticEngine *default_engine = [controller.haptics createEngineWithLocality:GCHapticsLocalityDefault];

	NSSet<GCHapticsLocality> *localities = controller.haptics.supportedLocalities;

	// If for some reason the default engine locality does not exists, we try
	// to create an engine for all supported localities.
	if (default_engine == nil) {
		for (GCHapticsLocality locality in [localities allObjects]) {
			CHHapticEngine *engine = [controller.haptics createEngineWithLocality:locality];
			if (engine != nil) {
				self.motion_engine = default_engine;
				break;
			}
		}
	} else {
		self.motion_engine = default_engine;
	}

	if (self.motion_engine != nil) {
		self.force_feedback = YES;
	} else {
		self.force_feedback = NO;
	}

	self.ff_effect_timestamp = 0;

	return self;
}

@end

JoypadMacOS::JoypadMacOS() {
	observer = [[JoypadMacOSObserver alloc] init];
	[observer startObserving];
}

JoypadMacOS::~JoypadMacOS() {
	if (observer) {
		[observer finishObserving];
		observer = nil;
	}
}

void JoypadMacOS::start_processing() {
	if (observer) {
		[observer startProcessing];
	}
	process_joypads();
}

CHHapticPattern *get_vibration_pattern(float p_weak_magnitude, float p_strong_magnitude, float p_duration) {
	// Creates a vibration pattern with 2 events, one per weak/strong magnitude.
	NSDictionary *hapticDict = @{
		CHHapticPatternKeyPattern : @[
			@{
				CHHapticPatternKeyEvent : @{
					CHHapticPatternKeyEventType : CHHapticEventTypeHapticContinuous,
					CHHapticPatternKeyTime : @(CHHapticTimeImmediate),
					CHHapticPatternKeyEventDuration : [NSNumber numberWithFloat:p_duration],

					CHHapticPatternKeyEventParameters : @[
						@{
							CHHapticPatternKeyParameterID : CHHapticEventParameterIDHapticIntensity,
							CHHapticPatternKeyParameterValue : [NSNumber numberWithFloat:p_weak_magnitude / 2]
						},
					],
				},
				CHHapticPatternKeyEvent : @{
					CHHapticPatternKeyEventType : CHHapticEventTypeHapticContinuous,
					CHHapticPatternKeyTime : @(CHHapticTimeImmediate),
					CHHapticPatternKeyEventDuration : [NSNumber numberWithFloat:p_duration],

					CHHapticPatternKeyEventParameters : @[
						@{
							CHHapticPatternKeyParameterID : CHHapticEventParameterIDHapticIntensity,
							CHHapticPatternKeyParameterValue : [NSNumber numberWithFloat:p_strong_magnitude]
						},
					],
				},
			},
		],
	};
	NSError *error;
	CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithDictionary:hapticDict error:&error];
	return pattern;
}

void JoypadMacOS::joypad_vibration_start(Joypad *p_joypad, float p_weak_magnitude, float p_strong_magnitude, float p_duration, uint64_t p_timestamp) {
	if (!p_joypad.force_feedback || p_weak_magnitude < 0.f || p_weak_magnitude > 1.f || p_strong_magnitude < 0.f || p_strong_magnitude > 1.f) {
		return;
	}

	if (p_joypad.pattern_player != nil) {
		joypad_vibration_stop(p_joypad, p_timestamp);
	}

	// Gets the default vibration pattern and creates a player with it.
	NSError *error;
	CHHapticPattern *pattern = get_vibration_pattern(p_weak_magnitude, p_strong_magnitude, p_duration);
	id<CHHapticPatternPlayer> player = [p_joypad.motion_engine createPlayerWithPattern:pattern error:&error];

	p_joypad.pattern_player = player;

	// When all players have stopped for an engine, stop the engine.
	[p_joypad.motion_engine notifyWhenPlayersFinished:^CHHapticEngineFinishedAction(NSError *_Nullable error) {
		return CHHapticEngineFinishedActionStopEngine;
	}];

	// Starts the engine and execute the vibration pattern
	[p_joypad.motion_engine startWithCompletionHandler:^(NSError *returnedError) {
		NSError *error;
		[player startAtTime:0 error:&error];
		p_joypad.ff_effect_timestamp = p_timestamp;
	}];
}

void JoypadMacOS::joypad_vibration_stop(Joypad *p_joypad, uint64_t p_timestamp) {
	if (!p_joypad.force_feedback) {
		return;
	}
	if (p_joypad.pattern_player == nil) {
		return;
	}

	NSError *error;
	[p_joypad.pattern_player stopAtTime:0 error:&error];
	p_joypad.pattern_player = nil;
	p_joypad.ff_effect_timestamp = p_timestamp;
}

@interface JoypadMacOSObserver ()

@property(assign, nonatomic) BOOL isObserving;
@property(assign, nonatomic) BOOL isProcessing;
@property(strong, nonatomic) NSMutableDictionary<NSNumber *, Joypad *> *connectedJoypads;
@property(strong, nonatomic) NSMutableArray<Joypad *> *joypadsQueue;

@end

@implementation JoypadMacOSObserver

- (instancetype)init {
	self = [super init];

	if (self) {
		[self godot_commonInit];
	}

	return self;
}

- (void)godot_commonInit {
	self.isObserving = NO;
	self.isProcessing = NO;
}

- (void)startProcessing {
	self.isProcessing = YES;

	for (GCController *controller in self.joypadsQueue) {
		[self addMacOSJoypad:controller];
	}

	[self.joypadsQueue removeAllObjects];
}

- (void)startObserving {
	if (self.isObserving) {
		return;
	}

	self.isObserving = YES;

	self.connectedJoypads = [NSMutableDictionary dictionary];
	self.joypadsQueue = [NSMutableArray array];

	// get told when controllers connect, this will be called right away for
	// already connected controllers
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(controllerWasConnected:)
				   name:GCControllerDidConnectNotification
				 object:nil];

	// get told when controllers disconnect
	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(controllerWasDisconnected:)
				   name:GCControllerDidDisconnectNotification
				 object:nil];
}

- (void)finishObserving {
	if (self.isObserving) {
		[[NSNotificationCenter defaultCenter] removeObserver:self];
	}

	self.isObserving = NO;
	self.isProcessing = NO;

	self.connectedJoypads = nil;
	self.joypadsQueue = nil;
}

- (void)dealloc {
	[self finishObserving];
}

- (NSArray<NSNumber *> *)getAllKeysForController:(GCController *)controller {
	NSArray *keys = [self.connectedJoypads allKeys];
	NSMutableArray *final_keys = [NSMutableArray array];

	for (NSNumber *key in keys) {
		Joypad *joypad = [self.connectedJoypads objectForKey:key];
		if (joypad.controller == controller) {
			[final_keys addObject:key];
		}
	}

	return final_keys;
}

- (int)getJoyIdForController:(GCController *)controller {
	NSArray *keys = [self getAllKeysForController:controller];

	for (NSNumber *key in keys) {
		int joy_id = [key intValue];
		return joy_id;
	}

	return -1;
}

- (void)addMacOSJoypad:(GCController *)controller {
	// get a new id for our controller
	int joy_id = Input::get_singleton()->get_unused_joy_id();

	if (joy_id == -1) {
		print_verbose("Couldn't retrieve new joy ID.");
		return;
	}

	// assign our player index
	if (controller.playerIndex == GCControllerPlayerIndexUnset) {
		controller.playerIndex = [self getFreePlayerIndex];
	}

	// tell Godot about our new controller
	Input::get_singleton()->joy_connection_changed(joy_id, true, String::utf8([controller.vendorName UTF8String]));

	Joypad *joypad = [[Joypad alloc] init:controller];

	// add it to our dictionary, this will retain our controllers
	[self.connectedJoypads setObject:joypad forKey:[NSNumber numberWithInt:joy_id]];

	// set our input handler
	[self setControllerInputHandler:controller];
}

- (void)controllerWasConnected:(NSNotification *)notification {
	// get our controller
	GCController *controller = (GCController *)notification.object;

	if (!controller) {
		print_verbose("Couldn't retrieve new controller.");
		return;
	}

	if ([[self getAllKeysForController:controller] count] > 0) {
		print_verbose("Controller is already registered.");
	} else if (!self.isProcessing) {
		Joypad *joypad = [[Joypad alloc] init:controller];
		[self.joypadsQueue addObject:joypad];
	} else {
		[self addMacOSJoypad:controller];
	}
}

- (void)controllerWasDisconnected:(NSNotification *)notification {
	// find our joystick, there should be only one in our dictionary
	GCController *controller = (GCController *)notification.object;

	if (!controller) {
		return;
	}

	NSArray *keys = [self getAllKeysForController:controller];
	for (NSNumber *key in keys) {
		// tell Godot this joystick is no longer there
		int joy_id = [key intValue];
		Input::get_singleton()->joy_connection_changed(joy_id, false, "");

		// and remove it from our dictionary
		[self.connectedJoypads removeObjectForKey:key];
	}
}

- (GCControllerPlayerIndex)getFreePlayerIndex {
	bool have_player_1 = false;
	bool have_player_2 = false;
	bool have_player_3 = false;
	bool have_player_4 = false;

	if (self.connectedJoypads == nil) {
		NSArray *keys = [self.connectedJoypads allKeys];
		for (NSNumber *key in keys) {
			Joypad *joypad = [self.connectedJoypads objectForKey:key];
			GCController *controller = joypad.controller;
			if (controller.playerIndex == GCControllerPlayerIndex1) {
				have_player_1 = true;
			} else if (controller.playerIndex == GCControllerPlayerIndex2) {
				have_player_2 = true;
			} else if (controller.playerIndex == GCControllerPlayerIndex3) {
				have_player_3 = true;
			} else if (controller.playerIndex == GCControllerPlayerIndex4) {
				have_player_4 = true;
			}
		}
	}

	if (!have_player_1) {
		return GCControllerPlayerIndex1;
	} else if (!have_player_2) {
		return GCControllerPlayerIndex2;
	} else if (!have_player_3) {
		return GCControllerPlayerIndex3;
	} else if (!have_player_4) {
		return GCControllerPlayerIndex4;
	} else {
		return GCControllerPlayerIndexUnset;
	}
}

- (void)setControllerInputHandler:(GCController *)controller {
	// Hook in the callback handler for the correct gamepad profile.
	// This is a bit of a weird design choice on Apples part.
	// You need to select the most capable gamepad profile for the
	// gamepad attached.
	if (controller.extendedGamepad != nil) {
		// The extended gamepad profile has all the input you could possibly find on
		// a gamepad but will only be active if your gamepad actually has all of
		// these...
		_weakify(self);
		_weakify(controller);

		controller.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
			_strongify(self);
			_strongify(controller);

			int joy_id = [self getJoyIdForController:controller];

			if (element == gamepad.buttonA) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::A,
						gamepad.buttonA.isPressed);
			} else if (element == gamepad.buttonB) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::B,
						gamepad.buttonB.isPressed);
			} else if (element == gamepad.buttonX) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::X,
						gamepad.buttonX.isPressed);
			} else if (element == gamepad.buttonY) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::Y,
						gamepad.buttonY.isPressed);
			} else if (element == gamepad.leftShoulder) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::LEFT_SHOULDER,
						gamepad.leftShoulder.isPressed);
			} else if (element == gamepad.rightShoulder) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::RIGHT_SHOULDER,
						gamepad.rightShoulder.isPressed);
			} else if (element == gamepad.dpad) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_UP,
						gamepad.dpad.up.isPressed);
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_DOWN,
						gamepad.dpad.down.isPressed);
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_LEFT,
						gamepad.dpad.left.isPressed);
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_RIGHT,
						gamepad.dpad.right.isPressed);
			}

			if (element == gamepad.leftThumbstick) {
				float value = gamepad.leftThumbstick.xAxis.value;
				Input::get_singleton()->joy_axis(joy_id, JoyAxis::LEFT_X, value);
				value = -gamepad.leftThumbstick.yAxis.value;
				Input::get_singleton()->joy_axis(joy_id, JoyAxis::LEFT_Y, value);
			} else if (element == gamepad.rightThumbstick) {
				float value = gamepad.rightThumbstick.xAxis.value;
				Input::get_singleton()->joy_axis(joy_id, JoyAxis::RIGHT_X, value);
				value = -gamepad.rightThumbstick.yAxis.value;
				Input::get_singleton()->joy_axis(joy_id, JoyAxis::RIGHT_Y, value);
			} else if (element == gamepad.leftTrigger) {
				float value = gamepad.leftTrigger.value;
				Input::get_singleton()->joy_axis(joy_id, JoyAxis::TRIGGER_LEFT, value);
			} else if (element == gamepad.rightTrigger) {
				float value = gamepad.rightTrigger.value;
				Input::get_singleton()->joy_axis(joy_id, JoyAxis::TRIGGER_RIGHT, value);
			}

			if (element == gamepad.buttonOptions) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::BACK,
						gamepad.buttonOptions.isPressed);
			} else if (element == gamepad.buttonMenu) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::START,
						gamepad.buttonOptions.isPressed);
			}
		};
	} else if (controller.microGamepad != nil) {
		// micro gamepads were added in macOS 10.11 and feature just 2 buttons and a d-pad
		_weakify(self);
		_weakify(controller);

		controller.microGamepad.valueChangedHandler = ^(GCMicroGamepad *gamepad, GCControllerElement *element) {
			_strongify(self);
			_strongify(controller);

			int joy_id = [self getJoyIdForController:controller];

			if (element == gamepad.buttonA) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::A,
						gamepad.buttonA.isPressed);
			} else if (element == gamepad.buttonX) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::X,
						gamepad.buttonX.isPressed);
			} else if (element == gamepad.dpad) {
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_UP,
						gamepad.dpad.up.isPressed);
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_DOWN,
						gamepad.dpad.down.isPressed);
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_LEFT,
						gamepad.dpad.left.isPressed);
				Input::get_singleton()->joy_button(joy_id, JoyButton::DPAD_RIGHT,
						gamepad.dpad.right.isPressed);
			}
		};
	}

	///@TODO need to add support for controller.motion which gives us access to
	/// the orientation of the device (if supported)

	///@TODO need to add support for controllerPausedHandler which should be a
	/// toggle
}

@end

void JoypadMacOS::process_joypads() {
	NSArray *keys = [observer.connectedJoypads allKeys];

	for (NSNumber *key in keys) {
		int id = key.intValue;
		Joypad *joypad = [observer.connectedJoypads objectForKey:key];

		if (joypad.force_feedback) {
			Input *input = Input::get_singleton();
			uint64_t timestamp = input->get_joy_vibration_timestamp(id);

			if (timestamp > joypad.ff_effect_timestamp) {
				Vector2 strength = input->get_joy_vibration_strength(id);
				float duration = input->get_joy_vibration_duration(id);
				if (duration == 0) {
					duration = GCHapticDurationInfinite;
				}

				if (strength.x == 0 && strength.y == 0) {
					joypad_vibration_stop(joypad, timestamp);
				} else {
					joypad_vibration_start(joypad, strength.x, strength.y, duration, timestamp);
				}
			}
		}
	}
}
