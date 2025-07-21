# Surfside iOS Sample App

![Surfside Logo](https://surfside.io/wp-content/uploads/2022/01/surfside-logo-color.svg)

A comprehensive iOS sample application demonstrating the full capabilities of the **Surfside iOS Tracker SDK**. This SwiftUI-based app showcases event tracking, context management, commerce events, and debugging features in an interactive, user-friendly interface.

## 🎯 Purpose

This sample app is designed to:

- **Demonstrate** all key features of the Surfside iOS Tracker
- **Provide** a hands-on testing environment for developers
- **Showcase** best practices for iOS analytics implementation
- **Serve** as a reference implementation for production apps

## ✨ Features Demonstrated

### 📊 Event Tracking
- **Screen View Events**: Track user navigation and screen interactions
- **Custom Events**: Send custom analytics events with structured data
- **Commerce Events**: Track product views and purchase transactions
- **Application Lifecycle**: Monitor app install, foreground, and background events

### 🌍 Context Management
- **Location Context**: Set and update user location data (coordinates, city, state, country)
- **Source Context**: Manage account and source identification
- **Segment Context**: Categorize users into segments for targeted analytics

### 🔧 Developer Tools
- **Real-time Logging**: View all tracking events and API calls in the app
- **Debug Event Flow**: Test network connectivity and event delivery
- **Event Flushing**: Force immediate event delivery for testing

### 🎨 Modern UI Design
- **Organized Button Groups**: Logical sections for different functionality
- **Visual Feedback**: Color-coded sections and real-time status updates
- **Responsive Layout**: Optimized for various iOS device sizes

## 🏗️ Architecture Overview

### Project Structure
```
SurfsideApp/
├── SurfsideApp/
│   ├── SurfsideApp.swift          # App entry point
│   ├── ContentView.swift          # Main UI and tracking logic
│   └── SurfsideApp.xcodeproj      # Xcode project file
└── README.md                      # This file
```

### Dependencies
- **Surfside iOS Tracker**: Local Swift package dependency (`../surfside-ios-tracker`)
- **SwiftUI**: Modern declarative UI framework
- **Foundation**: Core iOS frameworks

## 🚀 Getting Started

### Prerequisites
- **Xcode 15.0+**
- **iOS 16.0+** deployment target
- **Swift 5.9+**

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/surfside-io/surfside-ios-sample-app.git
   cd surfside-ios-sample-app
   ```

2. **Open in Xcode:**
   ```bash
   open SurfsideApp/SurfsideApp.xcodeproj
   ```

3. **Build and run:**
   - Select your target device or simulator
   - Press `Cmd+R` to build and run the app

### Local Package Dependency
The app uses a local Swift package reference to `../surfside-ios-tracker`. Ensure the Surfside iOS Tracker package is available at the correct relative path.

## 📱 Using the Sample App

The app interface is organized into three main sections:

### 1. Initialize, Debug, Clear
- **Initialize Tracker**: Set up the Surfside tracker with development configuration
- **Debug Event Flow**: Test network connectivity and event delivery
- **Clear Logs**: Reset the log display for a fresh start

### 2. Set Contexts
- **Update Location**: Set location context (New York coordinates example)
- **Update Source**: Update account and source identification
- **Update Segment**: Categorize user into segments (e.g., "premium-users")

### 3. Fire Events
- **Track Screen View**: Send screen view events
- **Track Basic Event**: Send custom link click events
- **View Product**: Track commerce product view events
- **Purchase Product**: Track ecommerce purchase transactions

## 🔧 Implementation Details

### Tracker Initialization

The app uses `SurfsideHelper.createTracker()` to initialize the tracker with development environment settings:

```swift
let result = SurfsideHelper.createTracker(
    namespace: namespace,
    environment: .development,
    accountId: accountId,
    sourceId: sourceId
)
```

**Key Configuration:**
- **Environment**: `.development` (automatically configures endpoint and HTTP method)
- **Collector**: Events sent to `https://c-dev.surfside.io`
- **Account ID**: `"test-account-123"`
- **Source ID**: `"ios-sample-app"`

### Event Tracking Examples

#### Screen View Events
```swift
func trackScreenView() {
    _ = tracker.track(ScreenView(name: "Home"))
    tracker.emitter?.flush()
}
```

#### Commerce Events
```swift
func viewProduct() {
    let event = Ecommerce.productView(
        product: ProductEntity(
            id: "product-001",
            category: "Electronics",
            currency: "USD",
            price: 299.99
        )
    )
    _ = tracker.track(event)
}
```

### Context Management

#### Location Context
```swift
surfsideEvent.setLocation(
    latitude: "40.7128",
    longitude: "-74.0060",
    country_code: "US",
    state: "NY",
    city: "New York",
    trackerNamespaces: nil
)
```

#### Source Context
```swift
surfsideEvent.source(
    accountId: "updated-account-123",
    sourceId: "updated-source-456",
    trackerNamespaces: nil
)
```

#### Segment Context
```swift
surfsideEvent.segment(
    segmentId: "premium-users",
    trackerNamespaces: nil
)
```

## 🔍 Debugging and Testing

### Real-time Logging
The app provides comprehensive logging for all operations:
- ✅ Success indicators for completed operations
- ❌ Error messages with clear descriptions
- 🔍 Debug information for troubleshooting
- 🚀 Network flush confirmations

### Debug Event Flow
The debug function tests:
- Tracker initialization status
- Network connectivity
- Event delivery pipeline
- Immediate event flushing

### Event Verification
To verify events are being sent:
1. Use the "Debug Event Flow" button
2. Check the app logs for network activity
3. Monitor your Surfside analytics dashboard
4. Use network debugging tools (Charles, Proxyman, etc.)

## 🌐 Network Configuration

### Development Environment
- **Collector Endpoint**: `https://c-dev.surfside.io`
- **HTTP Method**: `POST`
- **Event Batching**: Disabled (immediate flush for testing)

### Production Considerations
For production apps, consider:
- Using `.production` environment
- Enabling event batching for performance
- Implementing proper error handling
- Adding network reachability checks

## 🎨 UI Design Principles

### Visual Organization
- **Color-coded sections**: Gray (system), Blue (contexts), Green (events)
- **Logical grouping**: Related functionality grouped together
- **Clear hierarchy**: Section headers and consistent button styling

### User Experience
- **Immediate feedback**: Real-time logging and status updates
- **Progressive disclosure**: Enable buttons only when tracker is ready
- **Error prevention**: Clear error messages and state management

## 🔧 Customization

### Adding New Events
1. Create a new tracking function in `ContentView.swift`
2. Add the corresponding UI button in the appropriate section
3. Include proper error handling and logging
4. Test with the debug flow functionality

### Modifying Contexts
Update the context functions to match your app's requirements:
- Change location coordinates and details
- Update account and source IDs
- Modify segment categories and values

### Styling Customization
The UI uses SwiftUI's built-in styling with custom:
- Background colors for section grouping
- Button styles for different action types
- Typography hierarchy for clear information structure

## 📚 Additional Resources

- [Surfside iOS Tracker Documentation](../surfside-ios-tracker/README.md)
- [Surfside Analytics Platform](https://surfside.io)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [iOS Analytics Best Practices](https://developer.apple.com/documentation/foundation/analytics)

## 🤝 Contributing

This sample app serves as a reference implementation. For improvements or bug fixes:

1. Fork the repository
2. Create a feature branch
3. Make your changes with proper testing
4. Submit a pull request with detailed description

## 📄 License

This sample app is provided under the same license as the Surfside iOS Tracker SDK.

---

**Built with ❤️ by the Surfside team to showcase the power of iOS analytics tracking.**
