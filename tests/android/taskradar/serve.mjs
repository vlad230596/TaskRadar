// Starts the synthetic TaskRadar API for the emulator QA package.
// The emulator reaches it as http://10.0.2.2:18743 (the host's loopback).
import { startFaultServer } from '../lib/fault-server.mjs';
import { createTaskRadarApi } from './fake-api.mjs';
import { QA } from './app.mjs';

await startFaultServer({ api: createTaskRadarApi(), port: QA.hostPort });
