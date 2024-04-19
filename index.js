import { discover } from 'loupedeck'

// Detects and opens first connected device
const device = await discover()

// Observe connect events
device.on('connect', () => {
    console.info('Connection successful!')
})

// React to button presses
device.on('down', ({ id }) => {
    console.info(`Button pressed: ${id}`)
})

// React to knob turns
device.on('rotate', ({ id, delta }) => {
    console.info(`Knob ${id} rotated: ${delta}`)
})
