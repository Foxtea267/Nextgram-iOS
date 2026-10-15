import Foundation
import UIKit
import SwiftSignalKit

public typealias ListViewTransaction = (@escaping () -> Void) -> Void

public final class ListViewTransactionQueue {
    private var transactions: [ListViewTransaction] = []
    public final var transactionCompleted: () -> Void = { }
    
    // MARK: NAGRAM
    // A transaction may complete before it returns (a size update that changes nothing,
    // withTransaction, addAfterTransactionsCompleted), and the next one is then started from
    // inside that completion, a dozen frames deeper. A few hundred of them queued behind one
    // asynchronous transaction overflowed the main thread's stack (about 300 levels, from the
    // crash logs). Up to maxNestedCompletions the nesting is kept exactly as it was, because
    // callers run code after their completion call and its order against the following
    // transactions is visible. Past that, completions are counted and the innermost level
    // starts their successors in a loop.
    private static let maxNestedCompletions = 64
    private var nestedCompletions = 0
    private var deferredCompletions = 0
    
    public init() {
    }
    
    public func addTransaction(_ transaction: @escaping ListViewTransaction) {
        precondition(Thread.isMainThread)
        let beginTransaction = self.transactions.count == 0
        self.transactions.append(transaction)
        
        if beginTransaction {
            self.begin(transaction)
        }
    }
    
    private func begin(_ transaction: ListViewTransaction) {
        transaction({ [weak self] in
            precondition(Thread.isMainThread)
            
            self?.endTransaction()
        })
    }
    
    private func endTransaction() {
        precondition(Thread.isMainThread)
        
        if self.nestedCompletions >= ListViewTransactionQueue.maxNestedCompletions {
            self.deferredCompletions += 1
            return
        }
        
        self.nestedCompletions += 1
        self.advance()
        while self.deferredCompletions > 0 {
            self.deferredCompletions -= 1
            self.advance()
        }
        self.nestedCompletions -= 1
    }
    
    private func advance() {
        self.transactionCompleted()
        if !self.transactions.isEmpty {
            let _ = self.transactions.removeFirst()
        }
        
        if let nextTransaction = self.transactions.first {
            self.begin(nextTransaction)
        }
    }
}
