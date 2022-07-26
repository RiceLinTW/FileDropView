//
//  FileDropView.swift
//  
//
//  Created by Rice Lin on 2022/7/18.
//

import SwiftUI
import ComposableArchitecture
import UniformTypeIdentifiers

public struct FileDropRequest {
  var fetch: ([NSItemProvider], [UTType]) -> Effect<[URL], FileDropError>
}

extension FileDropRequest {
  public static let live = Self.init { (providers, types) in
    Effect<[URL], FileDropError>.future { callback in
      var urls: [URL] = []
      
      let group = DispatchGroup.init()
      
      providers.forEach { provider in
        types.forEach { type in
          
          group.enter()
          
          provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
            if let error = error {
              callback(.failure(.error(error)))
            } else {
              
              guard
                let data = data,
                let url = URL(dataRepresentation: data, relativeTo: nil) else {
                  return
                }
              
              urls.append(url)
              
              group.leave()
            }
          }
        }
      }
      
      group.notify(queue: .global()) {
        callback(.success(urls))
      }
    }
  }
}

public enum FileDropError: Error, Equatable {
  public static func == (lhs: FileDropError, rhs: FileDropError) -> Bool {
    return lhs.desc == rhs.desc
  }
  
  case error(Error)
  
  public var desc: String {
    switch self {
    case .error(let error):
      return error.localizedDescription
    }
  }
}

public struct FileDropState: Equatable {
  
  var isTargeted: Bool = false
  var alert: AlertState<FileDropAction>?
  
  var isAllowMultiFiles: Bool = true
  var dropHintTitle: String = "Drop files here."
  var dropTypes: [UTType] = [.fileURL]
  
  var result: Result<[URL], FileDropError>?
  
  public init(isAllowMultiFiles: Bool = true, dropHintTitle: String = "Drop files here.", dropTypes: [UTType] = [.fileURL]) {
    self.isAllowMultiFiles = isAllowMultiFiles
    self.dropHintTitle = dropHintTitle
    self.dropTypes = dropTypes
  }
}

public enum FileDropAction: Equatable {
  case fileDropped([NSItemProvider])
  case targeted(Bool)
  case multiFilesNotAllowed
  case alertDismiss
  case getFileURLs(Result<[URL], FileDropError>)
}

public struct FileDropViewEnvironment {
  
  var dropRequest: FileDropRequest
  var mainQueue: AnySchedulerOf<DispatchQueue>
  
  public init(dropRequest: FileDropRequest, mainQueue: AnySchedulerOf<DispatchQueue>) {
    self.dropRequest = dropRequest
    self.mainQueue = mainQueue
  }
}

public let fileDropReducer = Reducer<FileDropState, FileDropAction, FileDropViewEnvironment>.init { state, action, environment in
  switch action {
  case .fileDropped(let providers):
    return environment.dropRequest
      .fetch(providers, state.dropTypes)
      .receive(on: environment.mainQueue)
      .catchToEffect(FileDropAction.getFileURLs)
  case .targeted(let toggle):
    state.isTargeted = toggle
    return .none
  case .multiFilesNotAllowed:
    state.alert = .init(
      title: .init("Error"),
      message: .init("Load multiple files is not allowed."),
      dismissButton: .cancel(.init("OK"), action: .send(.alertDismiss))
    )
    return .none
  case .alertDismiss:
    state.alert = nil
    return .none
  case .getFileURLs(let result):
    state.result = result
    return .none
  }
}

public struct FileDropView<Content>: View where Content: View {
  
  private let store: Store<FileDropState, FileDropAction>
  private let resultView: () -> Content?
  
  public var body: some View {
    WithViewStore(store) { viewStore in
      VStack {
        if let resultView = resultView() {
          resultView
        } else {
          Text(viewStore.dropHintTitle)
            .frame(width: 300, height: 300, alignment: .center)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                  style: StrokeStyle(lineWidth: 2, dash: [10])
                )
            )
        }
      }
      .onDrop(of: viewStore.dropTypes, isTargeted: viewStore.binding(get: \.isTargeted, send: FileDropAction.targeted)) { providers, location in
        
        if !viewStore.isAllowMultiFiles && providers.count > 1 {
          viewStore.send(.multiFilesNotAllowed)
          return false
        } else {
          viewStore.send(.fileDropped(providers))
          return true
        }
      }
      .alert(
        self.store.scope(state: \.alert),
        dismiss: .alertDismiss
      )
    }
  }
  
  public init(store: Store<FileDropState, FileDropAction>, @ViewBuilder resultView: @escaping () -> Content?) {
    self.store = store
    self.resultView = resultView
  }
}
